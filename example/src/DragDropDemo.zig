//! Drag & Drop (`DragEvent` + `DataTransfer`) and `<input type="file">`
//! metadata inspector demo.

// 1. Imports
const std = @import("std");
const webapi = @import("webapi");

// 2. Shortcuts on imports
const DragDropDemo = @This();
const dom = webapi.dom;
const Event = webapi.Event;
const zjb = webapi.zjb;

// 3. File-level struct members
allocator: std.mem.Allocator,

// 7. Public functions
/// Attaches `#drop-zone` drag/drop listeners and `#drop-file-input` change listener.
pub fn bind(self: *DragDropDemo) void {
    const doc = dom.document();
    if (doc.getElementById("drop-zone")) |zone| {
        defer zone.release();
        zone.addEventListener("dragenter", DragDropDemo, self, onDropZoneDragOver);
        zone.addEventListener("dragover", DragDropDemo, self, onDropZoneDragOver);
        zone.addEventListener("dragleave", DragDropDemo, self, onDropZoneDragLeave);
        zone.addEventListener("drop", DragDropDemo, self, onDropZoneDrop);
    }
    if (doc.getElementById("drop-file-input")) |input| {
        defer input.release();
        webapi.boundEventListener(
            DragDropDemo,
            "change",
            input.handle,
            onDropFileInputChange,
            self,
        );
    }
}

// 9. Private declarations
fn setDropZoneActive(active: bool) void {
    const drop_zone = dom.document().getElementById("drop-zone") orelse return;
    defer drop_zone.release();
    const classes = drop_zone.classList();
    defer classes.release();
    if (active) {
        classes.add("drag-over");
    } else {
        classes.remove("drag-over");
    }
}

fn onDropZoneDragOver(_: *DragDropDemo, ev: Event.DragEvent) void {
    ev.preventDefault();
    setDropZoneActive(true);
    const dt = ev.dataTransfer();
    if (!dt.isNull()) {
        defer dt.release();
        dt.setDropEffect(.copy);
    }
}

fn onDropZoneDragLeave(_: *DragDropDemo, _: Event.DragEvent) void {
    setDropZoneActive(false);
}

fn onDropZoneDrop(self: *DragDropDemo, ev: Event.DragEvent) void {
    ev.preventDefault();
    setDropZoneActive(false);

    const dt = ev.dataTransfer();
    if (dt.isNull()) {
        dom.document().setElemText("drop-output", "Drop event had no DataTransfer.");
        return;
    }
    defer dt.release();

    const file_list = dt.files();
    defer file_list.release();

    if (file_list.len() > 0) {
        if (dom.document().getElementById("drop-file-input")) |input_el| {
            defer input_el.release();
            input_el.setFiles(file_list);
        }
        self.renderFileListMetadata(file_list);
        return;
    }

    if (dt.getDataAlloc(self.allocator, "text/plain") catch null) |dropped_text| {
        defer self.allocator.free(dropped_text);
        if (dropped_text.len > 0) {
            var out_buf: [512]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &out_buf,
                "No files dropped (received text/plain, {d} bytes):\n{s}",
                .{ dropped_text.len, dropped_text[0..@min(dropped_text.len, 240)] },
            ) catch "No files dropped (received text/plain).";
            dom.document().setElemText("drop-output", msg);
            return;
        }
    }

    dom.document().setElemText("drop-output", "Dropped item contained no files.");
}

fn onDropFileInputChange(self: *DragDropDemo, ev_h: zjb.Handle) void {
    const ev = Event.fromHandle(ev_h);
    const target_h = ev.target();
    if (target_h.isNull()) return;
    defer target_h.release();

    const input_el = dom.Element.fromHandle(target_h);
    const file_list = input_el.files();
    if (file_list.isNull()) return;
    defer file_list.release();

    self.renderFileListMetadata(file_list);
}

fn renderFileListMetadata(self: *DragDropDemo, file_list: webapi.File.List) void {
    const count = file_list.len();
    if (count == 0) {
        dom.document().setElemText("drop-output", "No files selected.");
        return;
    }

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(self.allocator);
    out.print(self.allocator, "Files ({d}):\n", .{count}) catch return;

    var idx: usize = 0;
    var it = file_list.iterate();
    while (it.next()) |file| {
        defer file.release();
        idx += 1;

        var name_buf: [256]u8 = undefined;
        const fname = file.name(&name_buf);

        var mime_buf: [128]u8 = undefined;
        const mime = file.mimeType(&mime_buf);

        var rel_buf: [256]u8 = undefined;
        const rel_path = file.webkitRelativePath(&rel_buf);

        const lm = file.lastModified();
        const lm_date = webapi.Date.initFromTimestamp(@floatFromInt(lm));
        defer lm_date.release();
        var iso_buf: [64]u8 = undefined;
        const iso = lm_date.toISOString(&iso_buf);

        out.print(
            self.allocator,
            "\n[{d}] {s}\n    size: {d} bytes\n    type: {s}\n    lastModified: {s} ({d})",
            .{
                idx,
                if (fname.len > 0) fname else "(unnamed)",
                file.size(),
                if (mime.len > 0) mime else "(unknown)",
                if (iso.len > 0) iso else "n/a",
                lm,
            },
        ) catch return;

        if (rel_path.len > 0) {
            out.print(self.allocator, "\n    path: {s}", .{rel_path}) catch return;
        }
    }

    dom.document().setElemText("drop-output", out.items);
}
