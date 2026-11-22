import { keywordTag } from "./tagger.js";
import assert from "node:assert";
const cases = [
  ["Summarize top 5 BNB Chain news today with links", "research"],
  ["Dịch whitepaper sang tiếng Việt", "translation"],
  ["Viết code solidity cho hợp đồng staking", "coding"],
  ["Build a guide about capital", null],          // no false hits on "ui"/"api" inside words
  ["Thiết kế logo cho dự án", "design"],
  ["Phân tích coin BNB và biểu đồ giá tuần này", "trading"],
];
for (const [t, want] of cases) { assert.equal(keywordTag(t), want, t); }
console.log("keyword tagger ok", cases.length);
