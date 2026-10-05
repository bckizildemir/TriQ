let HttpsError;
try {
  ({ HttpsError } = require("firebase-functions/v2/https"));
} catch {
  HttpsError = class extends Error {
    constructor(code, message, details) {
      super(message);
      this.code = code;
      this.details = details;
    }
  };
}

const logger = require("firebase-functions/logger");

const PROVIDERS = {
  groq: {
    url: "https://api.groq.com/openai/v1/chat/completions",
    // llama-3.3-70b-versatile was decommissioned by Groq on 2026-08-16.
    defaultModel: "openai/gpt-oss-120b",
    secretName: "GROQ_API_KEY",
    headers(apiKey) {
      return {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      };
    },
  },
  openrouter: {
    url: "https://openrouter.ai/api/v1/chat/completions",
    defaultModel: "x-ai/grok-4.1-fast",
    secretName: "OPENROUTER_API_KEY",
    headers(apiKey) {
      return {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "com.ttb.app",
        "X-Title": "TTB",
      };
    },
  },
};

const MAX_QUESTION_LENGTH = 500;
const MAX_CATEGORY_LENGTH = 100;
const MAX_IDEA_LENGTH = 500;
const MAX_TOPIC_LENGTH = 300;
const MAX_EXCLUDING_ITEMS = 20;
const MAX_EXCLUDING_ITEM_LENGTH = 80;
const MAX_QUICK_ANSWER_LIMIT = 10;
const MAX_VARIATION_COUNT = 10;
const MAX_CATEGORY_ID_ITEMS = 20;
const MAX_CATEGORY_ID_LENGTH = 80;
const DEFAULT_TRIO_CATEGORY_IDS = [
  "Daily",
  "Personal",
  "Relationships",
  "Career",
  "Health",
  "Goals",
  "Creativity",
];

async function askAIQuestion(options) {
  requireAuthenticated(options.user);
  const question = normalizedRequiredString(options.data?.question, "question", MAX_QUESTION_LENGTH);
  const category = normalizedRequiredString(options.data?.category, "category", MAX_CATEGORY_LENGTH);
  const languageName = normalizedLanguageName(options.data?.languageName);
  const prompt = buildAskQuestionPrompt({ question, category, languageName });
  const content = await makeProviderCall({ ...options, prompt, maxTokens: 500 });
  return { responses: parseNumberedList(content, 3, { exactCount: true }) };
}

async function suggestAIAnswers(options) {
  requireAuthenticated(options.user);
  const question = normalizedRequiredString(options.data?.question, "question", MAX_QUESTION_LENGTH);
  const languageName = normalizedLanguageName(options.data?.languageName);
  const prompt = buildAnswerSuggestionPrompt({ question, languageName });
  const content = await makeProviderCall({ ...options, prompt, maxTokens: 500 });
  return { responses: parseNumberedList(content, 3, { exactCount: true }) };
}

async function suggestQuickAnswers(options) {
  requireAuthenticated(options.user);
  const question = normalizedRequiredString(options.data?.question, "question", MAX_QUESTION_LENGTH);
  const category = normalizedRequiredString(options.data?.category, "category", MAX_CATEGORY_LENGTH);
  const excluding = normalizedStringArray(options.data?.excluding, MAX_EXCLUDING_ITEMS, MAX_EXCLUDING_ITEM_LENGTH);
  const limit = normalizedPositiveInt(options.data?.limit, 5, 1, MAX_QUICK_ANSWER_LIMIT);
  const languageName = normalizedLanguageName(options.data?.languageName);
  const prompt = buildQuickAnswerSuggestionPrompt({ question, category, excluding, limit, languageName });
  const content = await makeProviderCall({ ...options, prompt, maxTokens: 500 });
  const responses = parseNumberedList(content, limit, { exactCount: false });
  if (responses.length === 0) {
    throw new HttpsError("data-loss", "Provider response did not include valid answers.", { reason: "parsing" });
  }
  return { responses: responses.slice(0, limit) };
}

async function generateQuestionPrompt(options) {
  requireAuthenticated(options.user);
  const idea = normalizedRequiredString(options.data?.idea, "idea", MAX_IDEA_LENGTH);
  const category = normalizedRequiredString(options.data?.category, "category", MAX_CATEGORY_LENGTH);
  const languageName = normalizedLanguageName(options.data?.languageName);
  const prompt = buildQuestionCreationPrompt({ idea, category, languageName });
  const content = await makeProviderCall({ ...options, prompt, maxTokens: 250 });
  const question = parseDraftQuestion(content);
  if (question.length < 8) {
    throw new HttpsError("data-loss", "Provider response did not include a valid question.", { reason: "empty-response" });
  }
  return { question };
}

async function generateQuestionVariations(options) {
  requireAuthenticated(options.user);
  const topic = normalizedRequiredString(options.data?.topic, "topic", MAX_TOPIC_LENGTH);
  const count = normalizedPositiveInt(options.data?.count, 3, 1, MAX_VARIATION_COUNT);
  const languageName = normalizedLanguageName(options.data?.languageName);
  const prompt = buildVariationPrompt({ topic, count, languageName });
  const content = await makeProviderCall({ ...options, prompt, maxTokens: 500 });
  const variations = parseQuestionVariations(content, count);
  if (variations.length < count) {
    logger.warn("generateQuestionVariations.insufficient", {
      topic,
      languageName,
      count,
      parsedCount: variations.length,
      contentLength: content.length,
      contentPreview: content.slice(0, 400),
    });
    throw new HttpsError("data-loss", "Provider response did not include enough variations.", {
      reason: "insufficient-responses",
      count: variations.length,
    });
  }
  return { variations: variations.slice(0, count) };
}

async function generateTrioQuestionSuggestions(options) {
  requireAuthenticated(options.user);
  const topic = normalizedRequiredString(options.data?.topic, "topic", MAX_TOPIC_LENGTH);
  const count = normalizedPositiveInt(options.data?.count, 3, 1, MAX_VARIATION_COUNT);
  const excluding = normalizedStringArray(options.data?.excluding, MAX_EXCLUDING_ITEMS, MAX_EXCLUDING_ITEM_LENGTH);
  const availableCategoryIds = normalizedCategoryIds(options.data?.availableCategoryIds);
  const languageName = normalizedLanguageName(options.data?.languageName);
  const prompt = buildTrioSuggestionPrompt({
    topic,
    count,
    excluding,
    availableCategoryIds,
    languageName,
  });
  const content = await makeProviderCall({ ...options, prompt, maxTokens: 650 });
  const result = parseTrioQuestionSuggestions(content, count, availableCategoryIds);

  if (result.suggestions.length < count) {
    logger.warn("generateTrioQuestionSuggestions.insufficient", {
      topic,
      languageName,
      count,
      parsedCount: result.suggestions.length,
      contentLength: content.length,
      contentPreview: content.slice(0, 400),
    });
    throw new HttpsError("data-loss", "Provider response did not include enough suggestions.", {
      reason: "insufficient-responses",
      count: result.suggestions.length,
    });
  }

  return {
    suggestions: result.suggestions.slice(0, count),
    suggestedCategoryId: result.suggestedCategoryId,
  };
}

async function makeProviderCall({
  prompt,
  fetchImpl = fetch,
  provider = process.env.AI_PROVIDER,
  model = process.env.AI_MODEL,
  groqApiKey,
  openRouterApiKey,
  maxTokens,
}) {
  const providerName = normalizedProvider(provider);
  const config = PROVIDERS[providerName];
  const apiKey = normalizedApiKey(providerName === "groq" ? groqApiKey : openRouterApiKey, config.secretName);
  const resolvedModel = normalizedModel(model, config.defaultModel);
  const body = {
    model: resolvedModel,
    messages: [{ role: "user", content: prompt }],
    max_tokens: maxTokens,
    temperature: 0.7,
    top_p: 1,
    stream: false,
  };
  // gpt-oss models spend max_tokens on reasoning first; keep it low so short limits still leave room for the answer.
  if (resolvedModel.startsWith("openai/gpt-oss")) {
    body.reasoning_effort = "low";
  }

  let response;
  try {
    response = await fetchImpl(config.url, {
      method: "POST",
      headers: config.headers(apiKey),
      body: JSON.stringify(body),
    });
  } catch (error) {
    throw new HttpsError("unavailable", "AI provider is currently unavailable.", { reason: "network" });
  }

  const payload = await safeJSON(response);
  if (!response.ok) {
    throw mapProviderHTTPError(response.status, payload);
  }

  const content = payload?.choices?.[0]?.message?.content;
  if (typeof content !== "string" || content.trim().length === 0) {
    logger.warn("makeProviderCall.emptyContent", { reason: "invalid-response" });
    throw new HttpsError("data-loss", "Provider response did not include content.", { reason: "invalid-response" });
  }

  return content.trim();
}

function mapProviderHTTPError(status, payload) {
  const message = payload?.error?.message || "AI provider request failed.";
  if (status === 401) {
    return new HttpsError("unauthenticated", "AI provider key is invalid.", { reason: "api-key-invalid" });
  }
  if (status === 403) {
    return new HttpsError("permission-denied", message, { reason: "provider-permission-denied" });
  }
  if (status === 429) {
    return new HttpsError("resource-exhausted", "AI provider rate limit exceeded.", { reason: "rate-limit" });
  }
  if (status >= 500 && status <= 599) {
    return new HttpsError("unavailable", "AI provider server error.", { reason: "server-error", status });
  }
  return new HttpsError("invalid-argument", message, { reason: "provider-invalid-request", status });
}

async function safeJSON(response) {
  try {
    return await response.json();
  } catch {
    logger.warn("safeJSON.parseFailed", { reason: "parsing" });
    throw new HttpsError("data-loss", "Provider response could not be parsed.", { reason: "parsing" });
  }
}

function requireAuthenticated(user) {
  if (!user?.uid) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }
}

function normalizedProvider(value) {
  const provider = typeof value === "string" ? value.trim().toLowerCase() : "groq";
  if (!PROVIDERS[provider]) {
    throw new HttpsError("failed-precondition", "AI provider is not configured.", { reason: "configuration" });
  }
  return provider;
}

function normalizedApiKey(value, secretName) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("failed-precondition", `${secretName} is not configured.`, { reason: "configuration" });
  }
  return value.trim();
}

function normalizedModel(value, fallback) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : fallback;
}

function normalizedRequiredString(value, field, maxLength) {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  const trimmed = value.trim().replace(/\s+/g, " ");
  if (!trimmed) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  if (trimmed.length > maxLength) {
    throw new HttpsError("invalid-argument", `${field} is too long.`);
  }
  return trimmed;
}

function normalizedStringArray(value, maxItems, maxItemLength) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter((item) => typeof item === "string")
    .map((item) => item.trim().replace(/\s+/g, " ").slice(0, maxItemLength))
    .filter(Boolean)
    .slice(0, maxItems);
}

function normalizedCategoryIds(value) {
  const ids = normalizedStringArray(value, MAX_CATEGORY_ID_ITEMS, MAX_CATEGORY_ID_LENGTH);
  return ids.length > 0 ? ids : DEFAULT_TRIO_CATEGORY_IDS;
}

function normalizedPositiveInt(value, fallback, min, max) {
  if (!Number.isInteger(value)) {
    return fallback;
  }
  return Math.min(Math.max(value, min), max);
}

function normalizedLanguageName(value) {
  return value === "English" ? "English" : "Turkish";
}

function parseNumberedList(content, expectedCount, { exactCount }) {
  let responses = content
    .split(/\r?\n/)
    .map((line) => line.trim())
    .map((line) => line.replace(/^[0-9]+[\.\-\)]\s*/, "").trim())
    .filter((line) => line.length >= 1)
    .filter((line) => !line.toLowerCase().includes("yanıt bulunamadı"));

  if (responses.length === 0) {
    responses = content
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line.length > 10);
  }

  responses = responses.filter((response) => response.length >= 2).slice(0, expectedCount);
  if (exactCount && responses.length !== expectedCount) {
    throw new HttpsError("data-loss", "Provider response did not include the expected number of answers.", {
      reason: "insufficient-responses",
      count: responses.length,
    });
  }
  return responses;
}

function parseDraftQuestion(content) {
  const firstLine = content.split(/\r?\n/).map((line) => line.trim()).find(Boolean) || content;
  return firstLine
    .replace(/^[0-9]+[\.\-\)]\s*/, "")
    .replace(/^["'“”]+|["'“”]+$/g, "")
    .trim();
}

function dedupeCaseInsensitive(items) {
  const seen = new Set();
  const out = [];
  for (const item of items) {
    const key = item.trim().toLowerCase();
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push(item.trim());
  }
  return out;
}

function isVariationPreambleLine(line) {
  const t = line.trim();
  if (!t) return true;
  const lower = t.toLowerCase();
  if (/^here\b/.test(lower) || /^işte\b/u.test(lower) || /^iste\b/.test(lower)) return true;
  if (t.endsWith(":") && !t.includes("?")) return true;
  return false;
}

function stripVariationListFormatting(line) {
  return line
    .trim()
    .replace(/^\s*(?:[-*•]\s*)?[0-9]+[\.\-:\)]\s*/, "")
    .replace(/^\s*[-*•]\s+/, "")
    .replace(/^#+\s*/, "")
    .trim();
}

function stripMarkdownEdges(normalized) {
  return normalized
    .replace(/^\*{1,3}|\*{1,3}$/g, "")
    .replace(/^_{1,3}|_{1,3}$/g, "")
    .replace(/^`+|`+$/g, "")
    .replace(/^["'“”‘’]+|["'“”‘’]+$/g, "")
    .trim();
}

function parseQuestionVariations(content, expectedCount) {
  const candidates = splitVariationCandidates(content);

  const strict = [];
  for (const c of candidates) {
    const n = normalizedQuestionVariation(c);
    if (n.length >= 2 && n.includes("?")) strict.push(n);
  }
  const strictDeduped = dedupeCaseInsensitive(strict);
  if (strictDeduped.length >= expectedCount) {
    return strictDeduped.slice(0, expectedCount);
  }

  const lenient = [];
  for (const c of candidates) {
    if (isVariationPreambleLine(c)) continue;
    const n = normalizedQuestionVariationLenient(c);
    if (n.length >= 8 && n.includes("?")) lenient.push(n);
  }

  const merged = dedupeCaseInsensitive([...strictDeduped, ...lenient]);
  return merged.slice(0, expectedCount);
}

function parseTrioQuestionSuggestions(content, expectedCount, availableCategoryIds) {
  const parsed = parseStructuredVariationContent(content);
  let suggestions = [];
  let rawCategory;

  if (Array.isArray(parsed)) {
    suggestions = parsed.filter((item) => typeof item === "string");
  } else if (parsed && typeof parsed === "object") {
    const candidateKeys = ["suggestions", "questions", "variations", "options", "items"];
    for (const key of candidateKeys) {
      if (Array.isArray(parsed[key])) {
        suggestions = parsed[key].filter((item) => typeof item === "string");
        break;
      }
    }
    rawCategory = parsed.suggestedCategoryId || parsed.categoryId || parsed.category;
  }

  if (suggestions.length === 0) {
    suggestions = parseQuestionVariations(content, expectedCount);
  } else {
    suggestions = dedupeCaseInsensitive(
      suggestions
        .map((item) => normalizedQuestionVariationLenient(item))
        .filter((item) => item.length >= 8 && item.includes("?"))
    );
  }

  const suggestedCategoryId = normalizedSuggestedCategoryId(rawCategory, availableCategoryIds);
  return {
    suggestions: suggestions.slice(0, expectedCount),
    suggestedCategoryId,
  };
}

function normalizedSuggestedCategoryId(value, availableCategoryIds) {
  if (typeof value !== "string") {
    return availableCategoryIds[0];
  }
  const trimmed = value.trim();
  const exact = availableCategoryIds.find((id) => id === trimmed);
  if (exact) return exact;
  const lower = trimmed.toLowerCase();
  return availableCategoryIds.find((id) => id.toLowerCase() === lower) || availableCategoryIds[0];
}

function splitVariationCandidates(content) {
  const structuredCandidates = structuredVariationCandidates(content);
  if (structuredCandidates.length > 0) {
    return structuredCandidates;
  }

  const lines = content
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  return lines.flatMap((line) => {
    const numberedParts = line
      .split(/(?=\s*(?:[-*•]\s*)?[0-9]+[\.\-:\)]\s+)/)
      .map((part) => part.trim())
      .filter(Boolean);

    return numberedParts.length > 1 ? numberedParts : [line];
  });
}

function structuredVariationCandidates(content) {
  const parsed = parseStructuredVariationContent(content);
  if (!parsed) {
    return [];
  }

  if (Array.isArray(parsed)) {
    return parsed.filter((item) => typeof item === "string");
  }

  if (typeof parsed === "object") {
    const candidateKeys = ["variations", "questions", "options", "items"];
    for (const key of candidateKeys) {
      if (Array.isArray(parsed[key])) {
        return parsed[key].filter((item) => typeof item === "string");
      }
    }
  }

  return [];
}

function parseStructuredVariationContent(content) {
  const trimmed = content.trim();
  const fencedMatch = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  const jsonCandidate = fencedMatch ? fencedMatch[1].trim() : trimmed;

  if (!/^[\[{]/.test(jsonCandidate)) {
    return null;
  }

  try {
    return JSON.parse(jsonCandidate);
  } catch {
    return null;
  }
}

function normalizedQuestionVariation(line) {
  let normalized = stripVariationListFormatting(line);
  normalized = stripMarkdownEdges(normalized);
  const questionMarkIndex = normalized.lastIndexOf("?");
  if (questionMarkIndex === -1) {
    return "";
  }

  normalized = normalized.slice(0, questionMarkIndex + 1).trim();
  return stripMarkdownEdges(normalized);
}

function normalizedQuestionVariationLenient(line) {
  if (isVariationPreambleLine(line)) return "";
  let normalized = stripVariationListFormatting(line);
  normalized = stripMarkdownEdges(normalized);
  if (!normalized) return "";
  const questionMarkIndex = normalized.lastIndexOf("?");
  if (questionMarkIndex !== -1) {
    normalized = normalized.slice(0, questionMarkIndex + 1).trim();
  } else {
    normalized = normalized.replace(/\.+\s*$/, "").trim();
    if (!normalized) return "";
    normalized = `${normalized}?`;
  }
  return stripMarkdownEdges(normalized);
}

function buildAskQuestionPrompt({ question, category, languageName }) {
  if (languageName === "English") {
    return `You are a helpful assistant. For every question, you provide exactly 3 distinct, clear, and useful answers.

Category: ${category}
Question: ${question}

Please give exactly 3 different answers, one per line, numbered 1-3.
Every answer should be clear, concise, different from the others, practical, appropriate for the category, and written in ${languageName}.

Return only the numbered answers and nothing else.`;
  }
  return `Sen yardımsever bir asistansın ve her soruya tam olarak 3 ayrı, net ve faydalı yanıt veriyorsun.

Kategori: ${category}
Soru: ${question}

Lütfen tam olarak 3 farklı yanıt ver, her birini ayrı satırda, 1-3 numaralandırılmış olarak.
Her yanıt net, öz, diğerlerinden farklı, kategoriye uygun ve ${languageName} olmalı.

Sadece numaralandırılmış yanıtları ver, başka açıklama ekleme.`;
}

function buildAnswerSuggestionPrompt({ question, languageName }) {
  if (languageName === "English") {
    return `You are a warm and supportive personal growth assistant.

Question: ${question}

Suggest 3 different, thoughtful, and sincere answers to this question. Each answer should sound like the person's own inner voice, offer a different perspective, stay under 60 words, and be written in ${languageName}.

Return only the numbered answers and nothing else.`;
  }
  return `Sen samimi ve destekleyici bir kişisel gelişim asistanısın.

Soru: ${question}

Bu soruya birbirinden farklı, düşündürücü ve samimi 3 yanıt öner. Her yanıt kişinin kendi iç sesini yansıtır gibi olmalı, farklı bir bakış açısı sunmalı, 60 kelimeyi geçmemeli ve ${languageName} olmalı.

Sadece numaralandırılmış yanıtları ver, başka açıklama ekleme.`;
}

function buildQuickAnswerSuggestionPrompt({ question, category, excluding, limit, languageName }) {
  const exclusionText = excluding.length ? excluding.join(", ") : languageName === "English" ? "None" : "Yok";
  if (languageName === "English") {
    return `You create short, natural quick-answer chips for a journaling app.

Category: ${category}
Question: ${question}
Number of answers needed: ${limit}
Avoid these answers: ${exclusionText}

Return up to ${limit} concise, chip-friendly, common, plausible answers. Each answer should usually be 1 to 4 words and never more than 6 words. Write in ${languageName}. Return only numbered answers.`;
  }
  return `Bir günlük uygulaması için kısa ve doğal hazır cevap chip'leri üretiyorsun.

Kategori: ${category}
Soru: ${question}
Gereken cevap sayısı: ${limit}
Bunlardan kaçın: ${exclusionText}

En fazla ${limit} kısa, chip içinde rahat görünen, yaygın ve makul cevap ver. Cevaplar genelde 1 ila 4 kelime olsun, 6 kelimeyi geçmesin. ${languageName} yaz. Sadece numaralandırılmış cevapları ver.`;
}

function buildQuestionCreationPrompt({ idea, category, languageName }) {
  if (languageName === "English") {
    return `You are a creative editor who writes questions for TTB.

Goal: From the user's idea, generate exactly one question that is best answered with exactly 3 answers.

Category: ${category}
User idea: ${idea}

Write only 1 natural, simple question that strongly suggests a trio structure. It must match TTB's tone: favorites, tastes, memories, daily moments, and conversation starters. The sentence must end with a question mark. Write in ${languageName}.

Return only the question text.`;
  }
  return `Sen TTB için soru yazan yaratıcı bir editörsün.

Amaç: Kullanıcının fikrinden, tam olarak 3 cevapla yanıtlanmaya uygun tek bir soru üret.

Kategori: ${category}
Kullanıcı fikri: ${idea}

Sadece 1 doğal, sade soru yaz. Soru üçlü yapıyı hissettirsin ve TTB'nin tonuna uygun olsun: favoriler, zevkler, anılar, günlük anlar, sohbet başlatıcıları. Sorunun sonu soru işareti ile bitsin. ${languageName} yaz.

Sadece soru metnini ver.`;
}

function buildVariationPrompt({ topic, count, languageName }) {
  if (languageName === "English") {
    return `You are a creative question generator for a "Top 3" style Q&A app.

Given a topic, generate ${count} distinct question variations. Each variation should be answerable with exactly 3 items, use a different angle, feel conversational, and end with a question mark.

Topic: ${topic}

Return exactly ${count} numbered questions. No explanation.`;
  }
  return `Sen "Top 3" tarzı bir soru-cevap uygulaması için yaratıcı soru üreten bir asistansın.

Verilen konudan ${count} farklı soru varyasyonu üret. Her varyasyon tam olarak 3 öğe ile cevaplanabilir olmalı, konunun farklı bir açısını kullanmalı, konuşma diline yakın olmalı ve soru işareti ile bitmeli.

Konu: ${topic}

Tam olarak ${count} adet numaralandırılmış soru döndür, her birini ayrı satıra yaz. Açıklama ekleme.`;
}

function buildTrioSuggestionPrompt({ topic, count, excluding, availableCategoryIds, languageName }) {
  const excludedText = excluding.length ? excluding.join("\n- ") : languageName === "English" ? "None" : "Yok";
  const categoryText = availableCategoryIds.join(", ");

  if (languageName === "English") {
    return `You are a creative question editor for TTB, a Top 3 style Q&A app.

Generate ${count} distinct question suggestions from the user's text. Each suggestion must be answerable with exactly 3 items, use a different angle, feel conversational, and end with a question mark.

User text: ${topic}
Available category IDs: ${categoryText}
Avoid repeating these previous suggestions:
- ${excludedText}

Return only valid JSON with this exact shape:
{"suggestions":["Question?","Question?","Question?"],"suggestedCategoryId":"OneAvailableCategoryId"}

Use only one of the available category IDs. Write the questions in ${languageName}.`;
  }

  return `TTB için yaratıcı bir soru editörüsün. TTB, "Top 3" tarzı bir soru-cevap uygulamasıdır.

Kullanıcının metninden ${count} farklı soru önerisi üret. Her öneri tam olarak 3 öğe ile cevaplanabilir olmalı, farklı bir açı kullanmalı, konuşma diline yakın olmalı ve soru işareti ile bitmeli.

Kullanıcı metni: ${topic}
Kullanılabilir kategori ID'leri: ${categoryText}
Bu önceki önerileri tekrar etme:
- ${excludedText}

Sadece şu yapıda geçerli JSON döndür:
{"suggestions":["Soru?","Soru?","Soru?"],"suggestedCategoryId":"KullanılabilirKategoriID"}

Sadece kullanılabilir kategori ID'lerinden birini kullan. Soruları ${languageName} yaz.`;
}

module.exports = {
  askAIQuestion,
  generateQuestionPrompt,
  generateQuestionVariations,
  generateTrioQuestionSuggestions,
  mapProviderHTTPError,
  parseDraftQuestion,
  parseNumberedList,
  parseQuestionVariations,
  parseTrioQuestionSuggestions,
  suggestAIAnswers,
  suggestQuickAnswers,
};
