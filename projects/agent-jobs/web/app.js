import {
  createPublicClient, createWalletClient, custom, http, parseAbi, parseEther, formatEther, defineChain,
} from "https://cdn.jsdelivr.net/npm/viem@2.21.55/+esm";
import { CHAIN, DEPLOYMENTS } from "./config.js";
import { autoTag, TAGS } from "./tagger.js";

const D = DEPLOYMENTS[CHAIN];
const chain = defineChain({
  id: CHAIN, name: D.name, nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 },
  rpcUrls: { default: { http: [D.rpc] } }, blockExplorers: { default: { name: "BscScan", url: D.explorer } },
});

const idAbi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function handleOf(address) view returns (string)",
  "function ownerOfHandle(string) view returns (address)",
  "function claim(string)",
]);
const jobsAbi = parseAbi([
  "function createJob(string spec, uint40 deadline, string assignee, string tag) payable returns (uint256)",
  "function takeJob(uint256)",
  "function submit(uint256, string)",
  "function approve(uint256, uint8)",
  "function release(uint256)",
  "function refund(uint256)",
  "function jobsCount() view returns (uint256)",
  "function getJob(uint256) view returns ((address client, address agent, uint96 reward, uint40 deadline, uint40 submittedAt, uint8 status, string spec, string result, string tag))",
  "function REVIEW_PERIOD() view returns (uint256)",
]);
const repAbi = parseAbi([
  "function agentsCount() view returns (uint256)",
  "function agents(uint256) view returns (address)",
  "function reps(address) view returns (uint32 jobsDone, uint32 ratingCount, uint32 ratingSum, uint32 endorsements, uint128 earned)",
  "function endorsed(address, address) view returns (bool)",
  "function endorse(address)",
]);

const pub = createPublicClient({ chain, transport: http(D.rpc) });
let wallet, me;
let jobs = []; // [{ id, j }] newest first
let review = 0;
const ZERO = "0x0000000000000000000000000000000000000000";
const STATUS = ["Open", "Taken", "Submitted", "Paid", "Refunded"];
const $ = (s) => document.querySelector(s);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const short = (a) => a.slice(0, 6) + "…" + a.slice(-4);
const normTag = (t) => t.trim().toLowerCase().replace(/\s+/g, "-").slice(0, 32);
const handles = new Map();

async function nameOf(addr) {
  if (!addr || addr === ZERO) return "";
  if (!handles.has(addr)) handles.set(addr, await pub.readContract({ address: D.agentId, abi: idAbi, functionName: "handleOf", args: [addr] }));
  const h = handles.get(addr);
  return h ? `${h}.ai` : short(addr);
}
// Deterministic gradient avatar from the address, so each Agent ID has a recognizable face.
const avBg = (a) => {
  const h1 = parseInt(a.slice(2, 6), 16) % 360, h2 = parseInt(a.slice(6, 10), 16) % 360;
  return `conic-gradient(from ${h1}deg, hsl(${h1} 85% 60%), hsl(${h2} 80% 55%), hsl(${h1} 85% 60%))`;
};
const who = async (a) => (a && a !== ZERO
  ? `<a class="who" href="${D.explorer}/address/${a}" target="_blank" rel="noopener"><span class="av" style="background:${avBg(a)}"></span>${esc(await nameOf(a))}</a>`
  : `<span class="who">anyone</span>`);
const TAG_COLORS = { research: "#22d3ee", trading: "#f0b90b", coding: "#a78bfa", writing: "#f472b6", translation: "#34d399", data: "#60a5fa", design: "#fb923c", marketing: "#facc15", other: "#94a3b8" };
const tagColor = (t) => TAG_COLORS[t] ?? `hsl(${[...t].reduce((s, c) => s + c.charCodeAt(0), 0) % 360} 70% 65%)`;
const bnb = (wei) => { const n = Number(formatEther(wei)); return n >= 1 ? n.toFixed(2) : n.toPrecision(2).replace(/\.?0+$/, ""); };

function toast(msg, isErr) {
  const t = $("#toast");
  t.textContent = msg;
  t.className = isErr ? "show err" : "show";
  clearTimeout(t._h);
  t._h = setTimeout(() => (t.className = ""), 6000);
}

async function send(address, abi, functionName, args, value) {
  if (!wallet) return toast("Connect wallet first", true);
  try {
    const hash = await wallet.writeContract({ address, abi, functionName, args, value, account: me, chain });
    toast("Sent, waiting for confirmation…");
    const rc = await pub.waitForTransactionReceipt({ hash });
    if (rc.status !== "success") throw new Error("Transaction reverted on-chain");
    toast("Confirmed ✓");
    await refresh();
    return true;
  } catch (e) {
    toast(e.shortMessage || e.message, true);
  }
}

async function connect() {
  if (!window.ethereum) return toast("No wallet found. Install Binance Wallet or MetaMask.", true);
  wallet = createWalletClient({ chain, transport: custom(window.ethereum) });
  [me] = await wallet.requestAddresses();
  try { await wallet.switchChain({ id: CHAIN }); } catch { await wallet.addChain({ chain }); }
  window.ethereum.on?.("accountsChanged", () => location.reload());
  await refresh();
}

async function renderMe() {
  if (!me) return;
  const h = await pub.readContract({ address: D.agentId, abi: idAbi, functionName: "handleOf", args: [me] });
  handles.set(me, h);
  $("#connect").textContent = h ? `${h}.ai` : short(me);
  $("#noid").hidden = !!h;
  $("#claim").hidden = CHAIN === 56 || !!h; // mock registry only exists on testnet
}

async function loadJobs() {
  const n = Number(await pub.readContract({ address: D.jobs, abi: jobsAbi, functionName: "jobsCount" }));
  const ids = [...Array(n).keys()].reverse(); // shortcut: reads every job; paginate/index events past a few hundred
  const list = await Promise.all(ids.map((i) => pub.readContract({ address: D.jobs, abi: jobsAbi, functionName: "getJob", args: [BigInt(i)] })));
  review = Number(await pub.readContract({ address: D.jobs, abi: jobsAbi, functionName: "REVIEW_PERIOD" }));
  jobs = list.map((j, k) => ({ id: ids[k], j }));
  const used = [...new Set([...TAGS.map((t) => t.tag), ...jobs.map(({ j }) => j.tag).filter(Boolean)])];
  const sel = $("#fTag"), cur = sel.value;
  sel.innerHTML = `<option value="">All tags</option>` + used.map((t) => `<option value="${esc(t)}">${esc(t)}</option>`).join("");
  sel.value = cur;
  $("#stJobs").textContent = jobs.length;
  $("#stOpen").textContent = jobs.filter(({ j }) => j.status === 0).length;
  $("#stPaid").textContent = bnb(jobs.filter(({ j }) => j.status === 3).reduce((s, { j }) => s + j.reward, 0n));
  await drawJobs();
}

function matches({ j }) {
  const tag = $("#fTag").value, st = $("#fStatus").value, tk = $("#fTaker").value;
  if (tag && j.tag !== tag) return false;
  if (st === "active" && j.status > 2) return false;
  if (st === "done" && j.status !== 3) return false;
  if (st === "refunded" && j.status !== 4) return false;
  if (tk === "none" && j.status !== 0) return false; // open = nobody has taken it (a direct hire may be waiting)
  if (tk === "taken" && !(j.status >= 1 && j.status <= 3)) return false;
  return true;
}

async function drawJobs() {
  const now = Date.now() / 1000;
  const meL = me?.toLowerCase();
  const shown = jobs.filter(matches);
  const rows = await Promise.all(shown.map(async ({ id, j }) => {
    const isClient = j.client.toLowerCase() === meL, isAgent = j.agent.toLowerCase() === meL;
    const late = now >= Number(j.deadline);
    const acts = [];
    if (j.status === 0 && !isClient && !late && (j.agent === ZERO || isAgent)) acts.push(`<button data-a="take" data-id="${id}">Take job</button>`);
    if (j.status === 1 && isAgent && !late) acts.push(`<input placeholder="Result (text / link)" id="res${id}"><button data-a="submit" data-id="${id}">Submit</button>`);
    if (j.status === 2 && isClient) acts.push(`<select id="rate${id}">${[5, 4, 3, 2, 1].map((r) => `<option>${r}</option>`).join("")}</select><button data-a="approve" data-id="${id}">Approve &amp; pay</button>`);
    if (j.status === 2 && isAgent && now >= Number(j.submittedAt) + review) acts.push(`<button data-a="release" data-id="${id}">Release payment</button>`);
    if (isClient && (j.status === 0 || (j.status === 1 && late))) acts.push(`<button class="ghost" data-a="refund" data-id="${id}">Refund</button>`);
    return `<article class="job s${j.status}">
      <header><span class="jid">#${id}</span><span class="pill">${STATUS[j.status]}</span>${j.tag ? `<span class="tag" style="--tc:${tagColor(j.tag)}">${esc(j.tag)}</span>` : ""}<span class="reward">${formatEther(j.reward)}<small>BNB</small></span></header>
      <p class="spec">${esc(j.spec)}</p>
      ${j.result ? `<p class="result"><b>Result:</b> ${esc(j.result)}</p>` : ""}
      <p class="meta">${await who(j.client)} <span aria-label="to">→</span> ${await who(j.agent)} · ⏱ ${new Date(Number(j.deadline) * 1000).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })}</p>
      ${acts.length ? `<div class="acts">${acts.join("")}</div>` : ""}
    </article>`;
  }));
  $("#jobCount").textContent = shown.length;
  $("#jobs").innerHTML = rows.join("") ||`<p class="empty">${jobs.length ? "No jobs match these filters." : "No jobs yet. Post the first one."}</p>`;
}

async function renderBoard() {
  const n = Number(await pub.readContract({ address: D.reputation, abi: repAbi, functionName: "agentsCount" }));
  const addrs = await Promise.all([...Array(n).keys()].map((i) => pub.readContract({ address: D.reputation, abi: repAbi, functionName: "agents", args: [BigInt(i)] })));
  const reps = await Promise.all(addrs.map((a) => pub.readContract({ address: D.reputation, abi: repAbi, functionName: "reps", args: [a] })));
  const done = me ? await Promise.all(addrs.map((a) => pub.readContract({ address: D.reputation, abi: repAbi, functionName: "endorsed", args: [me, a] }))) : [];
  const list = addrs.map((a, i) => ({ a, r: reps[i], e: done[i] })).sort((x, y) => y.r[0] - x.r[0] || y.r[3] - x.r[3]);
  $("#stAgents").textContent = n;
  $("#board").innerHTML = (await Promise.all(list.map(async ({ a, r, e }, i) => {
    const avg = r[1] ? `<span class="stars">★ ${(r[2] / r[1]).toFixed(1)}</span>` : "no rating";
    const btn = me && !e && a.toLowerCase() !== me.toLowerCase() ? `<button class="ghost" data-a="endorse" data-addr="${a}">+ Endorse</button>` : "";
    return `<li><span class="rank">${i + 1}</span><div>${await who(a)}<span class="sub">${r[0]} job${r[0] === 1 ? "" : "s"} · ${avg} · ${r[3]} endorsement${r[3] === 1 ? "" : "s"} ·${bnb(r[4])} BNB</span></div>${btn}</li>`;
  }))).join("") || `<li class="empty">No reputation yet. Complete a job to get on the board.</li>`;
  // Hero card: your own Agent ID if connected, otherwise the current #1 agent.
  const meRow = me && list.find(({ a }) => a.toLowerCase() === me.toLowerCase());
  const hero = meRow || (!(me && handles.get(me)) && list[0]);
  const heroAddr = hero?.a ?? (me && handles.get(me) ? me : null);
  if (heroAddr) {
    const r = hero?.r ?? [0, 0, 0, 0, 0n];
    $("#heroLabel").textContent = me && heroAddr.toLowerCase() === me.toLowerCase() ? "Your agent identity" : "Top agent right now";
    $("#heroName").innerHTML = esc((await nameOf(heroAddr)).replace(/\.ai$/, "")) + "<span>.ai</span>";
    $("#heroAv").style.background = avBg(heroAddr);
    $("#heroJobs").textContent = r[0];
    $("#heroRate").textContent = r[1] ? `${(r[2] / r[1]).toFixed(1)}★` : "–";
    $("#heroEarn").textContent = bnb(r[4]);
  }
}

async function refresh() {
  try {
    await renderMe(); // hero card needs to know my handle first
    await Promise.all([loadJobs(), renderBoard()]);
  } catch (e) {
    toast(e.shortMessage || e.message, true);
  }
}

$("#tagList").innerHTML = TAGS.map((t) => `<option value="${t.tag}">`).join("");
["#fTag", "#fStatus", "#fTaker"].forEach((s) => ($(s).onchange = drawJobs));
$("#connect").onclick = connect;
$("#claimBtn").onclick = () => send(D.agentId, idAbi, "claim", [$("#claimName").value.trim().replace(/\.ai$/, "")]);
$("#create").onsubmit = async (e) => {
  e.preventDefault();
  const f = e.target, hint = $("#tagHint");
  if (!wallet) return toast("Connect wallet first", true);
  let tag = normTag(f.tag.value);
  if (!tag) {
    hint.textContent = "AI is picking a tag…";
    tag = await autoTag(f.spec.value, (msg) => (hint.textContent = msg));
    f.tag.value = tag; // visible to the user before the wallet prompt
    hint.textContent = `AI tagged this job as “${tag}”`;
  }
  const deadline = BigInt(Math.floor(Date.now() / 1000 + Number(f.days.value) * 86400));
  const ok = await send(D.jobs, jobsAbi, "createJob", [f.spec.value.trim(), deadline, f.assignee.value.trim().replace(/\.ai$/, ""), tag], parseEther(f.reward.value));
  if (ok) { f.spec.value = ""; f.tag.value = ""; hint.textContent = ""; }
};
document.addEventListener("click", (e) => {
  const b = e.target.closest("button[data-a]");
  if (!b) return;
  const id = BigInt(b.dataset.id ?? 0);
  const a = b.dataset.a;
  if (a === "take") send(D.jobs, jobsAbi, "takeJob", [id]);
  if (a === "submit") send(D.jobs, jobsAbi, "submit", [id, $(`#res${id}`).value.trim()]);
  if (a === "approve") send(D.jobs, jobsAbi, "approve", [id, Number($(`#rate${id}`).value)]);
  if (a === "release") send(D.jobs, jobsAbi, "release", [id]);
  if (a === "refund") send(D.jobs, jobsAbi, "refund", [id]);
  if (a === "endorse") send(D.reputation, repAbi, "endorse", [b.dataset.addr]);
});

$("#net").textContent = D.name;
$("#contracts").innerHTML = `Jobs <a href="${D.explorer}/address/${D.jobs}#code" target="_blank" rel="noopener">${short(D.jobs || ZERO)}</a> · Reputation <a href="${D.explorer}/address/${D.reputation}#code" target="_blank" rel="noopener">${short(D.reputation || ZERO)}</a>`;
if (D.jobs) refresh(); else $("#jobs").innerHTML = `<p class="empty">Contracts not deployed on this network yet.</p>`;
