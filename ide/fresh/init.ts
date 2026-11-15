const editor = getEditor();

// Show .md files formatted instead of as raw text, the first time each one becomes the active tab.
// To edit the raw text, press Ctrl+P and run "Markdown: Source Mode"; it stays raw after that.
const rendered = new Set();

registerHandler("render_markdown_on_activate", async function (args) {
  try {
    const id = args.buffer_id;
    if (rendered.has(id)) return;
    const path = editor.getBufferPath(id) || "";
    if (!/\.(md|markdown)$/i.test(path)) return;
    rendered.add(id);
    await editor.runCommand("Markdown: Rendered Mode");
  } catch (e) {
    // An unhandled rejection would stop every plugin, so a failure here only leaves the file raw.
  }
});

editor.on("buffer_activated", "render_markdown_on_activate");

// A file passed on the command line is already active before this script runs.
(async function () {
  try {
    await editor.flush();
    await globalThis.render_markdown_on_activate({ buffer_id: editor.getActiveBufferId() });
  } catch (e) {
    // Same reason as above: never let a rejection escape.
  }
})();
