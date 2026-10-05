const test = require("node:test");
const assert = require("node:assert/strict");

const {
  askAIQuestion,
  generateQuestionPrompt,
  generateQuestionVariations,
  generateTrioQuestionSuggestions,
  parseTrioQuestionSuggestions,
  suggestAIAnswers,
  suggestQuickAnswers,
} = require("./aiProviderProxy");

function successFetch(content, assertions = () => {}) {
  return async (url, options) => {
    assertions(url, options);
    return {
      ok: true,
      status: 200,
      json: async () => ({
        choices: [{ message: { content } }],
      }),
    };
  };
}

function failureFetch(status, payload = { error: { message: "provider failed" } }) {
  return async () => ({
    ok: false,
    status,
    json: async () => payload,
  });
}

const baseOptions = {
  user: { uid: "user-1" },
  provider: "openrouter",
  model: "test-model",
  openRouterApiKey: "or-key",
  groqApiKey: "groq-key",
};

test("askAIQuestion rejects unauthenticated requests", async () => {
  await assert.rejects(
    () => askAIQuestion({
      ...baseOptions,
      user: null,
      data: { question: "Question?", category: "Life" },
      fetchImpl: successFetch("1. A\n2. B\n3. C"),
    }),
    /Authentication is required/
  );
});

test("missing provider secret returns configuration error", async () => {
  await assert.rejects(
    () => askAIQuestion({
      ...baseOptions,
      openRouterApiKey: "",
      data: { question: "Question?", category: "Life" },
      fetchImpl: successFetch("1. A\n2. B\n3. C"),
    }),
    /OPENROUTER_API_KEY is not configured/
  );
});

test("OpenRouter success response normalizes exactly 3 answers", async () => {
  const result = await askAIQuestion({
    ...baseOptions,
    data: { question: "Question?", category: "Life", languageName: "English" },
    fetchImpl: successFetch("1. First answer\n2. Second answer\n3. Third answer", (url, options) => {
      assert.equal(url, "https://openrouter.ai/api/v1/chat/completions");
      assert.equal(options.headers.Authorization, "Bearer or-key");
      assert.equal(JSON.parse(options.body).model, "test-model");
    }),
  });

  assert.deepEqual(result.responses, ["First answer", "Second answer", "Third answer"]);
});

test("Groq success response normalizes answer suggestions", async () => {
  const result = await suggestAIAnswers({
    ...baseOptions,
    provider: "groq",
    data: { question: "Question?", languageName: "English" },
    fetchImpl: successFetch("1. One\n2. Two\n3. Three", (url, options) => {
      assert.equal(url, "https://api.groq.com/openai/v1/chat/completions");
      assert.equal(options.headers.Authorization, "Bearer groq-key");
    }),
  });

  assert.deepEqual(result.responses, ["One", "Two", "Three"]);
});

test("Groq default model is a live model with low reasoning effort", async () => {
  // llama-3.3-70b-versatile was decommissioned by Groq on 2026-08-16 and now returns 404.
  await suggestAIAnswers({
    ...baseOptions,
    provider: "groq",
    model: undefined,
    data: { question: "Question?", languageName: "English" },
    fetchImpl: successFetch("1. One\n2. Two\n3. Three", (url, options) => {
      const body = JSON.parse(options.body);
      assert.equal(body.model, "openai/gpt-oss-120b");
      assert.equal(body.reasoning_effort, "low");
    }),
  });
});

test("non gpt-oss models do not get a reasoning effort", async () => {
  await suggestAIAnswers({
    ...baseOptions,
    data: { question: "Question?", languageName: "English" },
    fetchImpl: successFetch("1. One\n2. Two\n3. Three", (url, options) => {
      assert.equal(JSON.parse(options.body).reasoning_effort, undefined);
    }),
  });
});

test("malformed provider responses return parsing or invalid response errors", async () => {
  await assert.rejects(
    () => askAIQuestion({
      ...baseOptions,
      data: { question: "Question?", category: "Life" },
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => ({ choices: [] }),
      }),
    }),
    /Provider response did not include content/
  );

  await assert.rejects(
    () => askAIQuestion({
      ...baseOptions,
      data: { question: "Question?", category: "Life" },
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => {
          throw new Error("bad json");
        },
      }),
    }),
    /Provider response could not be parsed/
  );
});

test("provider 401, 403, 429, and 5xx errors map correctly", async () => {
  await assert.rejects(
    () => askAIQuestion({
      ...baseOptions,
      data: { question: "Question?", category: "Life" },
      fetchImpl: failureFetch(401),
    }),
    /AI provider key is invalid/
  );

  await assert.rejects(
    () => askAIQuestion({
      ...baseOptions,
      data: { question: "Question?", category: "Life" },
      fetchImpl: failureFetch(403, { error: { message: "forbidden: org-123 model gpt-x" } }),
    }),
    (error) => {
      assert.equal(error.code, "permission-denied");
      assert.equal(error.message, "AI provider request failed.");
      return true;
    }
  );

  await assert.rejects(
    () => askAIQuestion({
      ...baseOptions,
      data: { question: "Question?", category: "Life" },
      fetchImpl: failureFetch(429),
    }),
    /rate limit/
  );

  await assert.rejects(
    () => askAIQuestion({
      ...baseOptions,
      data: { question: "Question?", category: "Life" },
      fetchImpl: failureFetch(500),
    }),
    /server error/
  );
});

test("exact-count contract is preserved for 3-answer flows", async () => {
  await assert.rejects(
    () => askAIQuestion({
      ...baseOptions,
      data: { question: "Question?", category: "Life" },
      fetchImpl: successFetch("1. Only one\n2. Only two"),
    }),
    /expected number/
  );
});

test("quick answers, prompt generation, and variations normalize payloads", async () => {
  const quick = await suggestQuickAnswers({
    ...baseOptions,
    data: { question: "Question?", category: "Life", excluding: ["Coffee"], limit: 2, languageName: "English" },
    fetchImpl: successFetch("1. Tea\n2. Walk"),
  });
  assert.deepEqual(quick.responses, ["Tea", "Walk"]);

  const prompt = await generateQuestionPrompt({
    ...baseOptions,
    data: { idea: "movies", category: "Entertainment", languageName: "English" },
    fetchImpl: successFetch('"What are your top 3 comfort movies?"'),
  });
  assert.equal(prompt.question, "What are your top 3 comfort movies?");

  const variations = await generateQuestionVariations({
    ...baseOptions,
    data: { topic: "movies", count: 2, languageName: "English" },
    fetchImpl: successFetch("1. What are your top 3 comfort movies?\n2. Which 3 movie scenes do you replay most?"),
  });
  assert.deepEqual(variations.variations, [
    "What are your top 3 comfort movies?",
    "Which 3 movie scenes do you replay most?",
  ]);
});

test("question variations tolerate Markdown, quotes, bullets, and colon numbering", async () => {
  const variations = await generateQuestionVariations({
    ...baseOptions,
    data: { topic: "selam", count: 3, languageName: "Turkish" },
    fetchImpl: successFetch([
      '- 1: **"Selam verirken en çok kullandığın 3 ifade neler?"**',
      "* 2) 'Yeni tanıştığın birine soracağın 3 sıcak soru ne?'",
      "• 3- `Gün içinde seni gülümseten 3 selamlaşma anı hangileri?`.",
    ].join("\n")),
  });

  assert.deepEqual(variations.variations, [
    "Selam verirken en çok kullandığın 3 ifade neler?",
    "Yeni tanıştığın birine soracağın 3 sıcak soru ne?",
    "Gün içinde seni gülümseten 3 selamlaşma anı hangileri?",
  ]);
});

test("question variations tolerate single-line numbered output", async () => {
  const variations = await generateQuestionVariations({
    ...baseOptions,
    data: { topic: "travel", count: 3, languageName: "English" },
    fetchImpl: successFetch(
      "1. What are your top 3 city breaks? 2. Which 3 trips changed your perspective? 3. What 3 travel moments do you still talk about?"
    ),
  });

  assert.deepEqual(variations.variations, [
    "What are your top 3 city breaks?",
    "Which 3 trips changed your perspective?",
    "What 3 travel moments do you still talk about?",
  ]);
});

test("question variations ignore intro text before numbered output", async () => {
  const variations = await generateQuestionVariations({
    ...baseOptions,
    data: { topic: "coffee", count: 3, languageName: "English" },
    fetchImpl: successFetch(
      "Here are three options:\n1. What are your top 3 coffee orders? 2. Which 3 cafes feel like home? 3. What 3 coffee moments do you remember most?"
    ),
  });

  assert.deepEqual(variations.variations, [
    "What are your top 3 coffee orders?",
    "Which 3 cafes feel like home?",
    "What 3 coffee moments do you remember most?",
  ]);
});

test("question variations tolerate JSON array output", async () => {
  const variations = await generateQuestionVariations({
    ...baseOptions,
    data: { topic: "selam", count: 3, languageName: "Turkish" },
    fetchImpl: successFetch(JSON.stringify([
      "Selam verirken en çok kullandığın 3 ifade neler?",
      "Yeni tanıştığın birine soracağın 3 sıcak soru ne?",
      "Gün içinde seni gülümseten 3 selamlaşma anı hangileri?",
    ])),
  });

  assert.deepEqual(variations.variations, [
    "Selam verirken en çok kullandığın 3 ifade neler?",
    "Yeni tanıştığın birine soracağın 3 sıcak soru ne?",
    "Gün içinde seni gülümseten 3 selamlaşma anı hangileri?",
  ]);
});

test("question variations tolerate fenced JSON object output", async () => {
  const variations = await generateQuestionVariations({
    ...baseOptions,
    data: { topic: "movies", count: 2, languageName: "English" },
    fetchImpl: successFetch([
      "```json",
      JSON.stringify({
        variations: [
          "What are your top 3 comfort movies?",
          "Which 3 movie scenes do you replay most?",
        ],
      }),
      "```",
    ].join("\n")),
  });

  assert.deepEqual(variations.variations, [
    "What are your top 3 comfort movies?",
    "Which 3 movie scenes do you replay most?",
  ]);
});

test("question variations lenient pass appends question mark when line omits it", async () => {
  const variations = await generateQuestionVariations({
    ...baseOptions,
    data: { topic: "lotr", count: 3, languageName: "English" },
    fetchImpl: successFetch(
      [
        "1. What are your top three friendships in Lord of the Rings?",
        "2. Which three locations from Middle-earth would you most want to visit",
        "3. What three scenes do you never skip on a rewatch?",
      ].join("\n")
    ),
  });

  assert.equal(variations.variations.length, 3);
  assert.ok(variations.variations.every((v) => v.endsWith("?")));
  assert.ok(variations.variations.some((v) => v.includes("Middle-earth")));
});

test("question variations lenient pass fills when no line contains a question mark", async () => {
  const variations = await generateQuestionVariations({
    ...baseOptions,
    data: { topic: "travel", count: 3, languageName: "English" },
    fetchImpl: successFetch(
      [
        "1. What are your top three city breaks for a long weekend",
        "2. Which three trips changed your perspective on travel completely",
        "3. What three travel moments do you still tell stories about today",
      ].join("\n")
    ),
  });

  assert.equal(variations.variations.length, 3);
  assert.ok(variations.variations.every((v) => v.endsWith("?")));
});

test("question variations rejects garbage with no usable questions", async () => {
  await assert.rejects(
    () =>
      generateQuestionVariations({
        ...baseOptions,
        data: { topic: "x", count: 3, languageName: "English" },
        fetchImpl: successFetch("nope"),
      }),
    /did not include enough variations/
  );
});

test("trio suggestions return normalized questions and valid category", async () => {
  const result = await generateTrioQuestionSuggestions({
    ...baseOptions,
    data: {
      topic: "comfort foods",
      count: 3,
      availableCategoryIds: ["Daily", "Personal", "Relationships"],
      excluding: ["What are your top 3 soups?"],
      languageName: "English",
    },
    fetchImpl: successFetch(
      JSON.stringify({
        suggestions: [
          "Which 3 comfort foods feel like home?",
          "What are your 3 favorite rainy-day meals?",
          "Which 3 snacks always improve your mood?",
        ],
        suggestedCategoryId: "Personal",
      }),
      (_url, options) => {
        const prompt = JSON.parse(options.body).messages[0].content;
        assert.match(prompt, /comfort foods/);
        assert.match(prompt, /Daily, Personal, Relationships/);
        assert.match(prompt, /What are your top 3 soups/);
      }
    ),
  });

  assert.deepEqual(result, {
    suggestions: [
      "Which 3 comfort foods feel like home?",
      "What are your 3 favorite rainy-day meals?",
      "Which 3 snacks always improve your mood?",
    ],
    suggestedCategoryId: "Personal",
  });
});

test("trio suggestions fall back to first category for unknown provider category", () => {
  const result = parseTrioQuestionSuggestions(
    JSON.stringify({
      suggestions: [
        "Which 3 places feel calmest to you?",
        "What are your 3 favorite quiet routines?",
        "Which 3 moments help you reset?",
      ],
      suggestedCategoryId: "Unknown",
    }),
    3,
    ["Daily", "Personal"]
  );

  assert.equal(result.suggestedCategoryId, "Daily");
});

test("trio suggestions tolerate numbered output without category", async () => {
  const result = await generateTrioQuestionSuggestions({
    ...baseOptions,
    data: {
      topic: "travel memories",
      count: 3,
      availableCategoryIds: ["Daily", "Personal", "Goals"],
      languageName: "English",
    },
    fetchImpl: successFetch(
      "1. What are your top 3 travel memories?\n2. Which 3 trips changed your perspective?\n3. What 3 places would you revisit?"
    ),
  });

  assert.deepEqual(result.suggestions, [
    "What are your top 3 travel memories?",
    "Which 3 trips changed your perspective?",
    "What 3 places would you revisit?",
  ]);
  assert.equal(result.suggestedCategoryId, "Daily");
});
