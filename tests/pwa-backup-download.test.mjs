import assert from "node:assert/strict";
import { Blob } from "node:buffer";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const appSource = await readFile("pwa/app.js", "utf8");
const functionStart = appSource.indexOf("function downloadJson(");
const functionEnd = appSource.indexOf("\nfunction printReport(", functionStart);
assert.ok(functionStart >= 0 && functionEnd > functionStart, "downloadJson source must remain discoverable");
const downloadJsonSource = appSource.slice(functionStart, functionEnd);

test("Safari backup download keeps an attached anchor and delays one Blob URL revocation", () => {
  const scheduled = [];
  const revoked = [];
  const body = {
    children: [],
    append(node) {
      this.children.push(node);
      node.parent = this;
    }
  };
  let clickedWhileAttached = false;
  let revokedDuringClick = false;
  let anchor = null;
  const context = {
    Blob,
    Date,
    URL: {
      createObjectURL(value) {
        assert.ok(value instanceof Blob);
        return "blob:gym-backup-test";
      },
      revokeObjectURL(value) {
        revoked.push(value);
      }
    },
    document: {
      body,
      createElement(tag) {
        assert.equal(tag, "a");
        anchor = {
          click() {
            clickedWhileAttached = body.children.includes(this);
            revokedDuringClick = revoked.length > 0;
          },
          remove() {
            const index = body.children.indexOf(this);
            if (index >= 0) body.children.splice(index, 1);
            this.parent = null;
          }
        };
        return anchor;
      }
    },
    setTimeout(callback, delay) {
      scheduled.push({ callback, delay });
      return scheduled.length;
    }
  };
  vm.createContext(context);
  vm.runInContext(`${downloadJsonSource}\nglobalThis.downloadJson = downloadJson;`, context);

  vm.runInContext(`downloadJson(${JSON.stringify('{"private":"workout"}')}, false)`, context);

  assert.equal(clickedWhileAttached, true);
  assert.equal(revokedDuringClick, false);
  assert.equal(body.children.length, 0);
  assert.equal(anchor.parent, null);
  assert.equal(anchor.hidden, true);
  assert.equal(anchor.rel, "noopener");
  assert.match(anchor.download, /^gym-backup-\d{4}-\d{2}-\d{2}\.json$/);
  assert.equal(revoked.length, 0, "WebKit must retain the Blob URL after the synchronous click");
  assert.equal(scheduled.length, 1);
  assert.equal(scheduled[0].delay, 1000);

  scheduled[0].callback();
  assert.deepEqual(revoked, ["blob:gym-backup-test"]);
});
