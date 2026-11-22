// Auto-tags a job from its description, fully in the browser (no server, no API key).
// 1) keyword match (covers Vietnamese, which the small English model handles poorly)
// 2) otherwise a sentence-embedding model (MiniLM, ~23 MB, cached by the browser after first use)
//    picks the closest tag description by cosine similarity.

export const TAGS = [
  { tag: "research", desc: "research, find information, summarize news, market report, analysis of a topic", kw: ["research", "summar", "news", "report", "tóm tắt", "tin tức", "nghiên cứu", "tìm hiểu", "báo cáo"] },
  { tag: "trading", desc: "crypto trading, token price analysis, chart signals, on-chain data, DeFi yields", kw: ["trade", "trading", "price", "chart", "token", "defi", "yield", "giao dịch", "giá", "biểu đồ", "phân tích coin"] },
  { tag: "coding", desc: "write code, smart contract, solidity, bug fix, script, API integration, software development", kw: ["code", "solidity", "contract", "bug", "script", "api", "deploy", "lập trình", "sửa lỗi", "viết code"] },
  { tag: "writing", desc: "write an article, blog post, copywriting, documentation, social media post, content", kw: ["write", "article", "blog", "post", "copy", "content", "thread", "viết bài", "nội dung", "bài đăng"] },
  { tag: "translation", desc: "translate text between languages, localization", kw: ["translat", "locali", "dịch", "phiên dịch"] },
  { tag: "data", desc: "data collection, scraping, spreadsheet, dataset cleaning, labeling, statistics", kw: ["data", "scrap", "csv", "spreadsheet", "dataset", "label", "dữ liệu", "thống kê", "thu thập"] },
  { tag: "design", desc: "graphic design, logo, image generation, banner, UI mockup, video editing", kw: ["design", "logo", "image", "banner", "ui", "video", "thiết kế", "hình ảnh", "ảnh"] },
  { tag: "marketing", desc: "marketing campaign, community growth, promotion, airdrop campaign, SEO, outreach", kw: ["marketing", "campaign", "seo", "promot", "community", "growth", "quảng bá", "chiến dịch", "cộng đồng"] },
  { tag: "other", desc: "miscellaneous task", kw: [] },
];

let extractorP;
const getExtractor = (onStatus) =>
  (extractorP ??= import("https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.0.2").then(({ pipeline }) => {
    onStatus?.("Loading AI model (first time only)…");
    return pipeline("feature-extraction", "Xenova/all-MiniLM-L6-v2");
  }));

export function keywordTag(text) {
  const t = text.toLowerCase();
  let best = null, hits = 0;
  for (const { tag, kw } of TAGS) {
    // match at a word start so "ui" doesn't hit "build"; prefixes like "translat" still match "translate"
    const n = kw.filter((k) => new RegExp(`(^|[^\\p{L}\\p{N}])${k}`, "u").test(t)).length;
    if (n > hits) [best, hits] = [tag, n];
  }
  return best;
}

export async function autoTag(text, onStatus) {
  const kw = keywordTag(text);
  if (kw) return kw;
  try {
    const ext = await getExtractor(onStatus);
    onStatus?.("AI is picking a tag…");
    const out = (await ext([text, ...TAGS.map((t) => t.desc)], { pooling: "mean", normalize: true })).tolist();
    const sims = out.slice(1).map((v) => v.reduce((s, x, i) => s + x * out[0][i], 0));
    const i = sims.indexOf(Math.max(...sims));
    return sims[i] > 0.15 ? TAGS[i].tag : "other";
  } catch {
    return "other"; // model unavailable (offline / blocked CDN): never block posting a job
  }
}
