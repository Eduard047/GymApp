import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("iOS launch screen keeps the branded color and icon at the same spot as the intro splash", async () => {
  const info = await readFile("ios/GymApp-iOS/GymApp/Resources/Info.plist", "utf8");
  const launch = info.match(/<key>UILaunchScreen<\/key>\s*<dict>([\s\S]*?)<\/dict>/);

  assert.notEqual(launch, null, "UILaunchScreen must stay declared");
  assert.match(launch[1], /<key>UIColorName<\/key>\s*<string>LaunchBackground<\/string>/);
  assert.match(launch[1], /<key>UIImageName<\/key>\s*<string>BrandMark<\/string>/);
  // Centered on the whole screen (not the asymmetric safe area), exactly like the splash view.
  assert.match(launch[1], /<key>UIImageRespectsSafeAreaInsets<\/key>\s*<false\/>/);
  const splash = await readFile("ios/GymApp-iOS/GymApp/UI/Screens/IntroSplashView.swift", "utf8");
  assert.match(splash, /\.ignoresSafeArea\(\)/, "the splash must measure the full screen to match the launch screen");
});

test("iOS draws the intro splash before building the heavy app state, as one persistent overlay", async () => {
  const entry = await readFile("ios/GymApp-iOS/GymApp/App/GymAppIOS.swift", "utf8");
  const root = await readFile("ios/GymApp-iOS/GymApp/App/AppRootView.swift", "utf8");
  const init = entry.match(/init\(\) \{([\s\S]*?)\n    \}/);

  assert.notEqual(init, null, "AppBootstrap.init must exist");
  assert.equal(init[1].includes("start()"), false, "AppBootstrap.init must not build AppState synchronously");
  assert.equal(init[1].includes("AppState("), false);
  assert.equal(entry.includes(".task { await bootstrap.startIfNeeded() }"), true);
  assert.equal(entry.includes("IntroSplashView()"), true);
  assert.equal(root.includes("IntroSplashView()"), false, "the splash overlay lives at the app root, not twice");
  assert.equal(root.includes("@Binding private var showsIntro"), true);
});
