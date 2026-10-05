const test = require("node:test");
const assert = require("node:assert/strict");

const {
  imageSearchQuery,
  saveSuggestedAnswerImage,
  suggestAnswerImages,
} = require("./pexelsImageSuggestions");

test("imageSearchQuery handles common Turkish activity phrases", () => {
  assert.equal(imageSearchQuery("kahve içmek"), "kahve");
  assert.equal(imageSearchQuery("yürüyüş yapmak"), "yürüyüş yapan insan");
  assert.equal(imageSearchQuery("uyumak"), "uyuyan insan");
  assert.equal(imageSearchQuery("kitap okumak"), "kitap okumak");
});

test("suggestAnswerImages rejects unauthenticated calls", async () => {
  await assert.rejects(
    () => suggestAnswerImages({
      user: null,
      data: { slotIndex: 0, answerText: "kahve" },
      pexelsApiKey: "key",
      fetchImpl: async () => ({ ok: true, json: async () => ({ photos: [] }) }),
    }),
    /Authentication is required/
  );
});

test("suggestAnswerImages validates slot and text", async () => {
  await assert.rejects(
    () => suggestAnswerImages({
      user: { uid: "user-1" },
      data: { slotIndex: 4, answerText: "kahve" },
      pexelsApiKey: "key",
      fetchImpl: async () => ({ ok: true, json: async () => ({ photos: [] }) }),
    }),
    /slotIndex/
  );

  await assert.rejects(
    () => suggestAnswerImages({
      user: { uid: "user-1" },
      data: { slotIndex: 0, answerText: " " },
      pexelsApiKey: "key",
      fetchImpl: async () => ({ ok: true, json: async () => ({ photos: [] }) }),
    }),
    /answerText/
  );
});

test("suggestAnswerImages normalizes Pexels search results", async () => {
  let requestedURL;
  const result = await suggestAnswerImages({
    user: { uid: "user-1" },
    data: { slotIndex: 1, answerText: "kahve içmek", locale: "tr-TR" },
    pexelsApiKey: "pexels-key",
    fetchImpl: async (url, options) => {
      requestedURL = url;
      assert.equal(options.headers.Authorization, "pexels-key");
      return {
        ok: true,
        json: async () => ({
          photos: [
            {
              id: 123,
              url: "https://www.pexels.com/photo/coffee-123/",
              photographer: "Ada",
              photographer_url: "https://www.pexels.com/@ada",
              src: {
                tiny: "https://images.pexels.com/photos/123/tiny.jpeg",
                medium: "https://images.pexels.com/photos/123/medium.jpeg",
                large: "https://images.pexels.com/photos/123/large.jpeg",
                large2x: "https://images.pexels.com/photos/123/large2x.jpeg",
              },
            },
          ],
        }),
      };
    },
  });

  assert.equal(requestedURL.searchParams.get("query"), "kahve");
  assert.equal(requestedURL.searchParams.get("per_page"), "4");
  assert.equal(requestedURL.searchParams.get("locale"), "tr-TR");
  assert.equal(result.slotIndex, 1);
  assert.deepEqual(result.suggestions, [
    {
      id: "123",
      photoId: "123",
      thumbnailURL: "https://images.pexels.com/photos/123/tiny.jpeg",
      previewURL: "https://images.pexels.com/photos/123/medium.jpeg",
      fullSizeURL: "https://images.pexels.com/photos/123/large2x.jpeg",
      photographer: "Ada",
      photographerURL: "https://www.pexels.com/@ada",
      photoURL: "https://www.pexels.com/photo/coffee-123/",
    },
  ]);
});

test("suggestAnswerImages maps Pexels failures to unavailable", async () => {
  await assert.rejects(
    () => suggestAnswerImages({
      user: { uid: "user-1" },
      data: { slotIndex: 0, answerText: "kahve" },
      pexelsApiKey: "key",
      fetchImpl: async () => ({ ok: false, status: 500 }),
    }),
    /Image search is currently unavailable/
  );
});

test("saveSuggestedAnswerImage writes selected Pexels image to the answer slot path", async () => {
  const savedFiles = [];
  const result = await saveSuggestedAnswerImage({
    user: { uid: "user-1" },
    data: {
      questionId: "question-1",
      slotIndex: 2,
      suggestion: {
        photoId: "123",
        thumbnailURL: "https://images.pexels.com/photos/123/tiny.jpeg",
        previewURL: "https://images.pexels.com/photos/123/medium.jpeg",
        fullSizeURL: "https://images.pexels.com/photos/123/large.jpeg",
        photographer: "Ada",
        photographerURL: "https://www.pexels.com/@ada",
        photoURL: "https://www.pexels.com/photo/coffee-123/",
      },
    },
    bucket: {
      name: "bucket-name",
      file(path) {
        return {
          async save(buffer, options) {
            savedFiles.push({ path, buffer, options });
          },
        };
      },
    },
    fetchImpl: async () => ({
      ok: true,
      headers: { get: () => "image/jpeg" },
      arrayBuffer: async () => Buffer.from("image-bytes"),
    }),
  });

  assert.equal(savedFiles.length, 1);
  assert.equal(savedFiles[0].path, "answers/user-1/question-1/slot_2.jpg");
  assert.equal(savedFiles[0].options.contentType, "image/jpeg");
  assert.match(result.downloadURL, /answers%2Fuser-1%2Fquestion-1%2Fslot_2\.jpg/);
  assert.deepEqual(result.attribution, {
    provider: "pexels",
    photoId: "123",
    photographer: "Ada",
    photographerURL: "https://www.pexels.com/@ada",
    photoURL: "https://www.pexels.com/photo/coffee-123/",
  });
});

test("saveSuggestedAnswerImage rejects non-Pexels image URLs", async () => {
  await assert.rejects(
    () => saveSuggestedAnswerImage({
      user: { uid: "user-1" },
      data: {
        questionId: "question-1",
        slotIndex: 0,
        suggestion: {
          photoId: "123",
          fullSizeURL: "https://example.com/image.jpg",
        },
      },
      bucket: { name: "bucket", file: () => ({ save: async () => {} }) },
      fetchImpl: async () => ({ ok: true }),
    }),
    /Only Pexels image URLs/
  );
});
