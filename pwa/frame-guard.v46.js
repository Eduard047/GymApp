"use strict";

(() => {
  const root = document.documentElement;
  let topLevel = false;
  try {
    topLevel = window.top === window.self;
  } catch {
    topLevel = false;
  }

  window.__GYMAPP_TOP_LEVEL__ = topLevel;
  if (topLevel) {
    root.classList.remove("frame-pending");
    root.dataset.frameGuard = "top-level";
    return;
  }

  root.dataset.frameGuard = "blocked";
  const renderBlockedFrame = () => {
    const panel = document.createElement("main");
    panel.className = "frame-blocked-message";
    panel.setAttribute("role", "alert");
    const title = document.createElement("h1");
    title.textContent = "GymApp cannot run inside another site.";
    const message = document.createElement("p");
    message.textContent = "Open GymApp directly in a top-level browser tab.";
    panel.append(title, message);
    document.body.replaceChildren(panel);
    root.classList.add("frame-blocked");
    root.classList.remove("frame-pending");
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", renderBlockedFrame, { once: true });
  } else {
    renderBlockedFrame();
  }
})();
