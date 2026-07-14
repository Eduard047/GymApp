function dynamicExecution(source) {
  // ruleid: gymapp-javascript-dynamic-code-execution
  return eval(source);
}

function cleartextUrl() {
  // ruleid: gymapp-hardcoded-cleartext-url
  return "http://example.invalid/api";
}

function secureUrl() {
  // ok: gymapp-hardcoded-cleartext-url
  return "https://example.invalid/api";
}
