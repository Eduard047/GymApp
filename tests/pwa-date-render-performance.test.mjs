import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import test from "node:test";

const source = await readFile("pwa/app.js", "utf8");
const dates = source.slice(source.indexOf("function displayLocale()"), source.indexOf("function fmtLongDate("));
const render = source.slice(source.indexOf("function render()"), source.indexOf("function pendingActivationScreen("));
function fixture() {
  let constructions = 0;
  const context = vm.createContext({
    Intl: { DateTimeFormat: new Proxy(Intl.DateTimeFormat, { construct(target, args) {
      constructions += 1;
      return new target(...args);
    } }) },
    Date, Map, JSON, state: { language: "en" }, modal: null, activeAccount: null,
    app: { classList: { toggle() {} } }, document: { documentElement: {} },
    rememberVisibleScroll() {}, bindEvents() {}, requestAnimationFrame() {},
    restoreVisibleScroll() {}
  });
  vm.runInContext(`${dates}\n${render}`, context);
  return { context, constructions: () => constructions };
}

test("one PWA render reuses date formatters but preserves language, options and exact output", () => {
  const { context, constructions } = fixture();
  context.loginScreen = () => {
    const values = [];
    for (const language of ["en", "uk", "ru"]) {
      context.state.language = language;
      for (const options of [{ year: "numeric", month: "short", day: "numeric" },
        { year: "numeric", month: "long", day: "numeric", timeZone: "Pacific/Honolulu" }]) {
        context.options = options;
        for (const timestamp of [0, 1786667400000, 1792891800000]) {
          context.timestamp = timestamp;
          const actual = vm.runInContext("fmtDate(timestamp, options)", context);
          const locale = { en: "en-US", uk: "uk-UA", ru: "ru-RU" }[language];
          assert.equal(actual, new Intl.DateTimeFormat(locale, options).format(new Date(timestamp)));
          values.push(actual);
        }
      }
    }
    return values.join("|");
  };
  vm.runInContext("render()", context);
  assert.equal(constructions(), 6);
  assert.equal(vm.runInContext("renderDateFormatters", context), null);
  vm.runInContext("render()", context);
  assert.equal(constructions(), 12, "another render must see current browser settings");
});

test("failed PWA renders release date formatters and retain no dates or account content", () => {
  const { context } = fixture();
  context.loginScreen = () => { throw new Error("synthetic render failure"); };
  assert.throws(() => vm.runInContext("render()", context), /synthetic render failure/);
  assert.equal(vm.runInContext("renderDateFormatters", context), null);
});
