const featureOrder = ["files", "clips", "search", "stack", "pin", "recent", "drop"];
const touchbarAssetVersion = "touchbar-20260907-mobile-story-001";

function touchbarAsset(path) {
  return `${path}?v=${touchbarAssetVersion}`;
}

const featureData = {
  files: {
    eyebrow: "Files",
    title: "Files.",
    headline: "Files stay close.",
    copy: "Drop files into ShelfBar and reopen them from the Touch Bar without breaking the app you are in.",
    storyLines: [
      "Drop files into ShelfBar.",
      "Keep them parked on the Touch Bar.",
      "Reopen them without breaking flow."
    ],
    image: touchbarAsset("assets/touchbar/files.png"),
    appImage: "assets/app-pages/shelf.png",
    videoAliases: ["files"]
  },
  clips: {
    eyebrow: "Clips",
    title: "Clips.",
    headline: "Clipboard text gets its own shelf.",
    copy: "Keep useful snippets beside your files, with paste actions that stay one touch away.",
    storyLines: [
      "Copy text, links, or images.",
      "ShelfBar keeps them beside your files.",
      "Paste actions stay one touch away."
    ],
    image: touchbarAsset("assets/touchbar/clips.png"),
    appImage: "assets/app-pages/features.png",
    videoAliases: ["clips", "clipboard"]
  },
  search: {
    eyebrow: "Search",
    title: "Search.",
    headline: "Search without opening another window.",
    copy: "Type, narrow, clear, and close from the strip while the app window stays quiet.",
    storyLines: [
      "Start searching from the Touch Bar.",
      "Type to narrow the shelf.",
      "Clear or close without opening another window."
    ],
    image: touchbarAsset("assets/touchbar/search.png"),
    appImage: "assets/app-pages/features.png",
    videoAliases: ["search"]
  },
  stack: {
    eyebrow: "Stack",
    title: "Stack.",
    headline: "Stacks make clutter compact.",
    copy: "Group related files together on the Touch Bar without turning the shelf into a folder maze.",
    storyLines: [
      "Drag related files together.",
      "ShelfBar folds them into a compact stack.",
      "The shelf stays clean without becoming a folder maze."
    ],
    image: touchbarAsset("assets/touchbar/stack.png"),
    appImage: "assets/app-pages/shelf.png",
    videoAliases: ["stack"]
  },
  pin: {
    eyebrow: "Pin",
    title: "Pin.",
    headline: "Pin what should not move.",
    copy: "Important files stay at the front while the rest of the shelf keeps changing around them.",
    storyLines: [
      "Pin the items that matter.",
      "They stay at the front.",
      "The rest of the shelf keeps moving around them."
    ],
    image: touchbarAsset("assets/touchbar/pin.png"),
    appImage: "assets/app-pages/features.png",
    videoAliases: ["pin"]
  },
  recent: {
    eyebrow: "Recent",
    title: "Recent.",
    headline: "Recent work is one touch away.",
    copy: "Jump back to files and clipboard entries you just used without opening a separate history view.",
    storyLines: [
      "Recent work stays reachable.",
      "Files and clips return in one gesture.",
      "No separate history window required."
    ],
    image: touchbarAsset("assets/touchbar/recent.png"),
    appImage: "assets/app-pages/shelf.png",
    videoAliases: ["recent"]
  },
  drop: {
    eyebrow: "Drag & Drop",
    title: "Drag & Drop.",
    headline: "Drop targets stay readable.",
    copy: "ShelfBar gives drops a clear Touch Bar target while keeping the page focused on the real interface.",
    storyLines: [
      "Drag toward the Touch Bar.",
      "The drop target stays readable.",
      "Release when ShelfBar makes room."
    ],
    image: touchbarAsset("assets/touchbar/drop.png"),
    appImage: "assets/app-pages/shelf.png",
    videoAliases: ["drag-drop", "drop"]
  }
};

const appTabs = {
  general: {
    image: "assets/app-pages/general.png",
    alt: "ShelfBar General settings screenshot"
  },
  appearance: {
    image: "assets/app-pages/appearance.png",
    alt: "ShelfBar app Appearance settings screenshot"
  },
  features: {
    image: "assets/app-pages/features.png",
    alt: "ShelfBar app feature settings screenshot"
  },
  shelf: {
    image: "assets/app-pages/shelf.png",
    alt: "ShelfBar app Shelf preview screenshot"
  },
  about: {
    image: "assets/app-pages/about.png",
    alt: "ShelfBar app About screenshot"
  }
};

const videoExtensions = ["mp4", "webm", "mov"];
const productStages = new Set();
const imagePreloadCache = new Map();
let featureVideos = {};
let carouselIndex = 0;
let carouselTimer = 0;
let carouselPaused = false;
let carouselSwitchToken = 0;
let storyFeatureKey = "";

const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

function clamp(value, min = 0, max = 1) {
  return Math.min(max, Math.max(min, value));
}

function getFeature(key) {
  return featureData[key] || featureData.files;
}

function canProbeAssets() {
  return window.location.protocol === "http:" || window.location.protocol === "https:";
}

function preloadImage(src) {
  if (!src) return Promise.resolve();
  if (imagePreloadCache.has(src)) return imagePreloadCache.get(src);

  const image = new Image();
  image.decoding = "async";
  image.src = src;

  const ready = image.decode
    ? image.decode().catch(() => {})
    : new Promise(resolve => {
      image.onload = resolve;
      image.onerror = resolve;
    });

  imagePreloadCache.set(src, ready);
  return ready;
}

function preloadFeatureAssets(key) {
  const feature = getFeature(key);
  return Promise.all([
    preloadImage(feature.image),
    preloadImage(feature.appImage)
  ]);
}

function preloadSiteImages() {
  featureOrder.forEach(key => {
    preloadFeatureAssets(key);
  });
  Object.values(appTabs).forEach(tab => preloadImage(tab.image));
}

async function fileExists(path) {
  if (!canProbeAssets()) return false;

  try {
    const response = await fetch(path, { method: "HEAD", cache: "no-store" });
    return response.ok;
  } catch {
    return false;
  }
}

function candidateVideoPaths(key) {
  const aliases = getFeature(key).videoAliases || [key];
  return aliases.flatMap(name => videoExtensions.map(extension => `assets/videos/${name}.${extension}`));
}

async function resolveFeatureVideos(manifest = {}) {
  const resolved = {};

  await Promise.all(
    featureOrder.map(async key => {
      const aliases = [key, ...(getFeature(key).videoAliases || [])];
      const manifestPath = aliases
        .map(alias => manifest?.[alias])
        .find(path => typeof path === "string" && path.trim());

      if (manifestPath && await fileExists(manifestPath)) {
        resolved[key] = manifestPath;
        return;
      }

      for (const path of candidateVideoPaths(key)) {
        if (await fileExists(path)) {
          resolved[key] = path;
          return;
        }
      }
    })
  );

  featureVideos = resolved;
  productStages.forEach(stage => applyFeatureToStage(stage, stage.dataset.feature || "files", { force: true }));
}

function swapImage(image, src, alt, host) {
  if (!image || image.getAttribute("src") === src) return;
  if (host && !prefersReducedMotion.matches) {
    host.classList.remove("is-swapping");
    host.getBoundingClientRect();
    host.classList.add("is-swapping");
    window.setTimeout(() => host.classList.remove("is-swapping"), 520);
  }
  image.src = src;
  image.alt = alt;
}

function resetAndPlay(video) {
  if (!video) return;
  video.currentTime = 0;
  video.play().catch(() => {});
}

function applyFeatureToStage(stage, key, options = {}) {
  const featureKey = featureData[key] ? key : "files";
  const feature = getFeature(featureKey);
  const touchbarFrame = stage.querySelector("[data-touchbar-frame]");
  const touchbarImage = stage.querySelector("[data-touchbar-image]");
  const touchbarVideo = stage.querySelector("[data-touchbar-video]");
  const appFrame = stage.querySelector("[data-app-frame]");
  const appImage = stage.querySelector("[data-app-image]");
  const videoPath = featureVideos[featureKey];

  if (!options.force && stage.dataset.appliedFeature === featureKey) return;

  stage.dataset.feature = featureKey;
  stage.dataset.appliedFeature = featureKey;
  stage.setAttribute("aria-label", `ShelfBar ${feature.eyebrow} shown with real Touch Bar and app screenshots`);

  swapImage(touchbarImage, feature.image, `ShelfBar ${feature.eyebrow} on a real Touch Bar`, touchbarFrame);
  swapImage(appImage, feature.appImage, `ShelfBar app window for ${feature.eyebrow}`, appFrame);

  if (touchbarVideo) {
    touchbarVideo.pause();
    touchbarVideo.removeAttribute("src");
    touchbarVideo.load();
  }

  if (touchbarFrame) {
    touchbarFrame.classList.toggle("has-video", Boolean(videoPath));
  }

  if (touchbarVideo && videoPath) {
    touchbarVideo.src = videoPath;
    touchbarVideo.load();
    if (!prefersReducedMotion.matches && stage.dataset.variant !== "story") {
      resetAndPlay(touchbarVideo);
    }
  }
}

function initializeStages() {
  document.querySelectorAll("[data-product-stage]").forEach(stage => {
    productStages.add(stage);
    applyFeatureToStage(stage, stage.dataset.feature || "files", { force: true });
  });
}

function prepareCarouselSlide(direction) {
  const panel = document.querySelector(".carousel-panel");
  const viewport = document.querySelector(".carousel-viewport");
  if (!panel || !viewport || direction === 0) return null;

  viewport.querySelectorAll(".carousel-panel-ghost").forEach(ghost => ghost.remove());
  panel.classList.remove("is-entering-next", "is-entering-prev");

  const outgoing = panel.cloneNode(true);
  outgoing.setAttribute("aria-hidden", "true");
  outgoing.classList.remove("is-entering-next", "is-entering-prev");
  outgoing.classList.add("carousel-panel-ghost", direction > 0 ? "is-exiting-next" : "is-exiting-prev");
  outgoing.querySelectorAll("[id]").forEach(element => element.removeAttribute("id"));
  viewport.appendChild(outgoing);

  return () => {
    panel.getBoundingClientRect();
    panel.classList.add(direction > 0 ? "is-entering-next" : "is-entering-prev");

    const clearSlide = () => {
      panel.classList.remove("is-entering-next", "is-entering-prev");
      outgoing.remove();
    };

    outgoing.addEventListener("animationend", clearSlide, { once: true });
    window.setTimeout(clearSlide, 960);
  };
}

async function updateCarousel(index, direction = 1) {
  const switchToken = ++carouselSwitchToken;
  const featureKey = featureOrder[(index + featureOrder.length) % featureOrder.length];
  await preloadFeatureAssets(featureKey);
  if (switchToken !== carouselSwitchToken) return;

  const runSlide = prepareCarouselSlide(direction);
  const feature = getFeature(featureKey);
  const stage = document.querySelector("[data-carousel-stage]");
  const eyebrow = document.querySelector("[data-carousel-eyebrow]");
  const title = document.querySelector("[data-carousel-title]");
  const copy = document.querySelector("[data-carousel-copy]");
  const progress = document.querySelector("[data-carousel-progress]");

  carouselIndex = featureOrder.indexOf(featureKey);

  if (eyebrow) eyebrow.textContent = feature.eyebrow;
  if (title) title.textContent = feature.title;
  if (copy) copy.textContent = feature.copy;
  if (progress) progress.style.width = `${((carouselIndex + 1) / featureOrder.length) * 100}%`;
  if (stage) applyFeatureToStage(stage, featureKey);
  runSlide?.();
}

function scheduleCarousel() {
  window.clearInterval(carouselTimer);
  if (!carouselPaused && !prefersReducedMotion.matches) {
    carouselTimer = window.setInterval(() => {
      updateCarousel(carouselIndex + 1, 1);
    }, 4600);
  }
}

function setCarouselPaused(paused) {
  const toggle = document.querySelector("[data-carousel-toggle]");
  const state = document.querySelector("[data-carousel-state]");

  carouselPaused = paused;
  if (toggle) {
    toggle.classList.toggle("is-paused", carouselPaused);
    toggle.setAttribute("aria-label", carouselPaused ? "Play highlights" : "Pause highlights");
  }
  if (state) state.textContent = carouselPaused ? "Play" : "Pause";
  scheduleCarousel();
}

function updateStoryFeature() {
  const story = document.querySelector(".story");
  const stage = document.querySelector("[data-story-stage]");
  const copyBlock = document.querySelector(".story-copy");
  const title = document.querySelector("[data-story-title]");
  const lines = document.querySelector("[data-story-lines]");

  if (!story || !stage) return;

  const rect = story.getBoundingClientRect();
  const travel = Math.max(1, rect.height - window.innerHeight);
  const progress = clamp(-rect.top / travel);
  const index = Math.min(featureOrder.length - 1, Math.floor(progress * featureOrder.length));
  const key = featureOrder[index];
  const feature = getFeature(key);
  const lineItems = feature.storyLines || [feature.copy];
  const featureProgress = clamp(progress * featureOrder.length - index);
  const featureChanged = key !== storyFeatureKey;

  document.documentElement.style.setProperty("--story-progress", progress.toFixed(3));
  if (title) title.textContent = feature.headline;
  if (lines) {
    renderStoryLines(lines, lineItems);
    setStoryLineBrightness(lines, featureProgress);
    setStoryMediaClarity(lines, featureProgress);
  }
  applyFeatureToStage(stage, key);
  if (featureChanged) {
    storyFeatureKey = key;
    if (copyBlock && !prefersReducedMotion.matches) {
      copyBlock.classList.remove("is-sliding");
      stage.classList.remove("is-story-changing");
      copyBlock.getBoundingClientRect();
      copyBlock.classList.add("is-sliding");
      stage.classList.add("is-story-changing");
      window.setTimeout(() => copyBlock.classList.remove("is-sliding"), 620);
      window.setTimeout(() => stage.classList.remove("is-story-changing"), 620);
    }
  }
}

function renderStoryLines(container, lineItems) {
  const signature = lineItems.join("\n");
  if (container.dataset.storyText === signature) return;

  let characterIndex = 0;
  const lineNodes = lineItems.map(text => {
    const line = document.createElement("span");
    line.className = "story-line";
    line.setAttribute("aria-label", text);

    [...text].forEach(character => {
      const characterNode = document.createElement("span");
      characterNode.className = "story-char";
      characterNode.textContent = character;
      characterNode.dataset.charIndex = String(characterIndex);
      characterNode.setAttribute("aria-hidden", "true");
      line.appendChild(characterNode);
      characterIndex += character.trim() ? 1 : 0;
    });

    return line;
  });

  container.replaceChildren(...lineNodes);
  container.dataset.storyText = signature;
  container.dataset.storyCharCount = String(characterIndex);
}

function setStoryMediaClarity(container, progress) {
  const total = Number(container.dataset.storyCharCount || 0);
  if (!total || prefersReducedMotion.matches) {
    document.documentElement.style.setProperty("--story-media-clarity", "1");
    return;
  }

  const oneCharacterProgress = 1 / total;
  const clarityThreshold = Math.min(0.085, Math.max(0.022, oneCharacterProgress * 1.15));
  const clarity = clamp(progress / clarityThreshold);
  document.documentElement.style.setProperty("--story-media-clarity", clarity.toFixed(3));
}

function setStoryLineBrightness(container, progress) {
  const total = Number(container.dataset.storyCharCount || 0);
  if (!total) return;

  const litCount = prefersReducedMotion.matches ? total : Math.round(clamp(progress) * total);
  container.querySelectorAll(".story-char").forEach(character => {
    const index = Number(character.dataset.charIndex || 0);
    const isSpace = !character.textContent.trim();
    character.classList.toggle("is-lit", isSpace || index < litCount);
  });

  container.querySelectorAll(".story-line").forEach(line => {
    const chars = [...line.querySelectorAll(".story-char")].filter(character => character.textContent.trim());
    const lit = chars.filter(character => character.classList.contains("is-lit")).length;
    line.classList.toggle("is-active", lit > 0 && lit < chars.length);
    line.classList.toggle("is-complete", chars.length > 0 && lit >= chars.length);
  });
}

function updateHeroMotion() {
  const hero = document.querySelector(".hero");
  if (!hero) return;

  const rect = hero.getBoundingClientRect();
  const progress = clamp(-rect.top / Math.max(1, rect.height * 0.7));
  document.documentElement.style.setProperty("--hero-progress", progress.toFixed(3));
}

function updateScrollMotion() {
  updateHeroMotion();
  updateStoryFeature();
}

function armReveals() {
  const revealElements = document.querySelectorAll(".reveal");
  if (!("IntersectionObserver" in window)) {
    revealElements.forEach(element => element.classList.add("is-visible"));
    return;
  }

  const revealObserver = new IntersectionObserver(
    entries => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          revealObserver.unobserve(entry.target);
        }
      }
    },
    { threshold: 0.14 }
  );

  revealElements.forEach(element => revealObserver.observe(element));
}

function armHighlighter() {
  const trigger = document.querySelector("[data-highlight-trigger]");
  if (!trigger) return;

  const mask = trigger.querySelector(".highlighter-mask-rect");
  let drawFrame = 0;

  const setHighlightProgress = progress => {
    if (!mask) return;
    mask.setAttribute("width", String(Math.round(1000 * clamp(progress))));
  };

  const easeHighlight = progress => 1 - Math.pow(1 - progress, 4);

  const draw = () => {
    if (!mask) return;
    window.cancelAnimationFrame(drawFrame);
    setHighlightProgress(0);
    trigger.classList.remove("is-drawn");
    trigger.classList.add("is-drawing");

    if (prefersReducedMotion.matches) {
      setHighlightProgress(1);
      trigger.classList.remove("is-drawing");
      trigger.classList.add("is-drawn");
      return;
    }

    const startedAt = performance.now();
    const paint = now => {
      const progress = clamp((now - startedAt) / 820);
      setHighlightProgress(easeHighlight(progress));

      if (progress < 1) {
        drawFrame = window.requestAnimationFrame(paint);
      } else {
        setHighlightProgress(1);
        trigger.classList.remove("is-drawing");
        trigger.classList.add("is-drawn");
      }
    };

    drawFrame = window.requestAnimationFrame(paint);
  };

  if (!("IntersectionObserver" in window)) {
    draw();
    return;
  }

  const highlightObserver = new IntersectionObserver(
    entries => {
      if (entries.some(entry => entry.isIntersecting)) {
        draw();
      }
    },
    { rootMargin: "0px 0px -30% 0px", threshold: 0.01 }
  );

  highlightObserver.observe(trigger);

  trigger.addEventListener("pointerenter", draw);
  trigger.addEventListener("focusin", draw);
}

function armCarousel() {
  const carousel = document.querySelector("[data-carousel]");
  const previous = document.querySelector("[data-carousel-prev]");
  const next = document.querySelector("[data-carousel-next]");
  const toggle = document.querySelector("[data-carousel-toggle]");

  if (!carousel) return;

  previous?.addEventListener("click", () => {
    updateCarousel(carouselIndex - 1, -1);
    scheduleCarousel();
  });

  next?.addEventListener("click", () => {
    updateCarousel(carouselIndex + 1, 1);
    scheduleCarousel();
  });

  toggle?.addEventListener("click", () => setCarouselPaused(!carouselPaused));

  if ("IntersectionObserver" in window) {
    const carouselObserver = new IntersectionObserver(
      entries => {
        if (entries.some(entry => entry.isIntersecting)) {
          carousel.classList.add("controls-ready");
          scheduleCarousel();
          carouselObserver.disconnect();
        }
      },
      { threshold: 0.28 }
    );
    carouselObserver.observe(carousel);
  } else {
    carousel.classList.add("controls-ready");
    scheduleCarousel();
  }
}

function armAppTabs() {
  const container = document.querySelector("[data-app-tabs]");
  const image = document.querySelector("[data-app-tab-image]");
  if (!container || !image) return;

  container.querySelectorAll("[data-app-tab]").forEach(button => {
    button.addEventListener("click", () => {
      const key = button.dataset.appTab || "appearance";
      const data = appTabs[key] || appTabs.appearance;

      container.querySelectorAll("[data-app-tab]").forEach(tab => {
        tab.setAttribute("aria-selected", String(tab === button));
      });

      swapImage(image, data.image, data.alt, image.closest(".app-showcase-frame"));
    });
  });
}

function armQA() {
  const questions = document.querySelectorAll(".qa-question");
  questions.forEach(question => {
    question.addEventListener("click", () => {
      const answer = document.getElementById(question.getAttribute("aria-controls"));
      const shouldOpen = question.getAttribute("aria-expanded") !== "true";

      questions.forEach(otherQuestion => {
        const otherAnswer = document.getElementById(otherQuestion.getAttribute("aria-controls"));
        otherQuestion.setAttribute("aria-expanded", "false");
        if (otherAnswer) otherAnswer.setAttribute("aria-hidden", "true");
      });

      question.setAttribute("aria-expanded", String(shouldOpen));
      if (answer) answer.setAttribute("aria-hidden", String(!shouldOpen));
    });
  });
}

initializeStages();
preloadSiteImages();
armReveals();
armHighlighter();
armCarousel();
armAppTabs();
armQA();
updateCarousel(0, 0);
updateScrollMotion();

window.addEventListener("scroll", updateScrollMotion, { passive: true });
window.addEventListener("resize", updateScrollMotion);

if (canProbeAssets()) {
  fetch("assets/videos/manifest.json", { cache: "no-store" })
    .then(response => (response.ok ? response.json() : {}))
    .then(resolveFeatureVideos)
    .catch(() => resolveFeatureVideos({}));
}

window.__shelfbarPreview = {
  featureOrder,
  setCarousel: updateCarousel,
  setStoryFeature: key => {
    const feature = getFeature(key);
    const stage = document.querySelector("[data-story-stage]");
    const title = document.querySelector("[data-story-title]");
    const lines = document.querySelector("[data-story-lines]");
    if (title) title.textContent = feature.headline;
    if (lines) {
      renderStoryLines(lines, feature.storyLines || [feature.copy]);
      setStoryLineBrightness(lines, 1);
    }
    if (stage) applyFeatureToStage(stage, key);
  },
  resolvedVideos: () => ({ ...featureVideos })
};
