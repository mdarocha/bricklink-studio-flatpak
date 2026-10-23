// D-Bus API for ci/smoke-test.sh to drive and capture one app window.
// Points are offsets from the centre of the window's client area.
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Shell from 'gi://Shell';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

Gio._promisify(Shell.Screenshot, 'composite_to_stream');
Gio._promisify(Shell.Screenshot.prototype, 'screenshot_stage_to_content');

const OBJECT_PATH = '/io/github/mdarocha/BrickLinkStudio/SmokeTest';
const INTERFACE = `
<node>
  <interface name="io.github.mdarocha.BrickLinkStudio.SmokeTest">
    <method name="X11Display">
      <arg type="s" direction="out" name="display"/>
      <arg type="s" direction="out" name="xauthority"/>
    </method>
    <method name="WindowTitles">
      <arg type="as" direction="out" name="titles"/>
    </method>
    <method name="HasWindow">
      <arg type="s" direction="in" name="wm_class"/>
      <arg type="b" direction="out" name="found"/>
    </method>
    <method name="PlaceWindow">
      <arg type="s" direction="in" name="wm_class"/>
      <arg type="i" direction="in" name="width"/>
      <arg type="i" direction="in" name="height"/>
    </method>
    <method name="FrameSize">
      <arg type="s" direction="in" name="wm_class"/>
      <arg type="i" direction="out" name="width"/>
      <arg type="i" direction="out" name="height"/>
    </method>
    <method name="Hover">
      <arg type="s" direction="in" name="wm_class"/>
      <arg type="i" direction="in" name="dx"/>
      <arg type="i" direction="in" name="dy"/>
    </method>
    <method name="Click">
      <arg type="s" direction="in" name="wm_class"/>
      <arg type="i" direction="in" name="dx"/>
      <arg type="i" direction="in" name="dy"/>
    </method>
    <method name="CaptureWindow">
      <arg type="s" direction="in" name="wm_class"/>
      <arg type="s" direction="in" name="path"/>
    </method>
    <method name="CaptureScreen">
      <arg type="s" direction="in" name="path"/>
    </method>
  </interface>
</node>`;

// Unity only registers a click after it has seen the pointer arrive and settle.
const POINTER_SETTLE_MS = 200;

function sleep(ms) {
    return new Promise(resolve => {
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
            resolve();
            return GLib.SOURCE_REMOVE;
        });
    });
}

function findActor(wmClass) {
    const actor = global.get_window_actors().find(a => a.meta_window.get_wm_class() === wmClass);
    if (!actor) {
        throw new Error(`no window with WM_CLASS ${wmClass}`);
    }
    return actor;
}

function clientPoint(wmClass, dx, dy) {
    const window = findActor(wmClass).meta_window;
    const client = window.frame_rect_to_client_rect(window.get_frame_rect());
    return [client.x + client.width / 2 + dx, client.y + client.height / 2 + dy];
}

async function savePng(texture, path) {
    const stream = Gio.File.new_for_path(path).replace(null, false, Gio.FileCreateFlags.NONE, null);
    try {
        await Shell.Screenshot.composite_to_stream(texture, 0, 0, -1, -1, 1, null, 0, 0, 1, stream);
    } finally {
        stream.close(null);
    }
}

class SmokeTest {
    constructor() {
        const seat = Clutter.get_default_backend().get_default_seat();
        this._pointer = seat.create_virtual_device(Clutter.InputDeviceType.POINTER_DEVICE);
    }

    X11Display() {
        return [GLib.getenv('DISPLAY') ?? '', GLib.getenv('XAUTHORITY') ?? ''];
    }

    WindowTitles() {
        return global.get_window_actors()
            .map(a => a.meta_window)
            .filter(w => w.get_title())
            .map(w => `${w.get_wm_class()}: ${w.get_title()}`);
    }

    HasWindow(wmClass) {
        return global.get_window_actors().some(a => a.meta_window.get_wm_class() === wmClass);
    }

    FrameSize(wmClass) {
        const frame = findActor(wmClass).meta_window.get_frame_rect();
        return [frame.width, frame.height];
    }

    // Sizes the frame (title bar included) and centres it in the work area.
    PlaceWindow(wmClass, width, height) {
        const window = findActor(wmClass).meta_window;
        const area = window.get_work_area_current_monitor();
        window.activate(global.get_current_time());
        window.move_resize_frame(true,
            area.x + Math.round((area.width - width) / 2),
            area.y + Math.round((area.height - height) / 2),
            width, height);
    }

    async HoverAsync([wmClass, dx, dy], invocation) {
        await this._reply(invocation, () => this._moveTo(clientPoint(wmClass, dx, dy)));
    }

    async ClickAsync([wmClass, dx, dy], invocation) {
        await this._reply(invocation, async () => {
            const [x, y] = clientPoint(wmClass, dx, dy);
            await this._moveTo([x - 10, y - 10]);
            await this._moveTo([x, y]);
            this._pointer.notify_button(GLib.get_monotonic_time(), Clutter.BUTTON_PRIMARY, Clutter.ButtonState.PRESSED);
            await sleep(POINTER_SETTLE_MS);
            this._pointer.notify_button(GLib.get_monotonic_time(), Clutter.BUTTON_PRIMARY, Clutter.ButtonState.RELEASED);
            await sleep(POINTER_SETTLE_MS);
        });
    }

    // GNOME's own window screenshot: frame, rounded corners and shadow, transparent background.
    async CaptureWindowAsync([wmClass, path], invocation) {
        await this._reply(invocation, () => {
            const content = findActor(wmClass).paint_to_content(null);
            return savePng(content.get_texture(), path);
        });
    }

    async CaptureScreenAsync([path], invocation) {
        await this._reply(invocation, async () => {
            const [content] = await new Shell.Screenshot().screenshot_stage_to_content();
            await savePng(content.get_texture(), path);
        });
    }

    async _moveTo([x, y]) {
        this._pointer.notify_absolute_motion(GLib.get_monotonic_time(), x, y);
        await sleep(POINTER_SETTLE_MS);
    }

    async _reply(invocation, action) {
        try {
            await action();
            invocation.return_value(null);
        } catch (e) {
            invocation.return_error_literal(Gio.DBusError, Gio.DBusError.FAILED, `${e}`);
        }
    }
}

export default class SmokeTestExtension extends Extension {
    enable() {
        this._object = Gio.DBusExportedObject.wrapJSObject(INTERFACE, new SmokeTest());
        this._object.export(Gio.DBus.session, OBJECT_PATH);
    }

    disable() {
        this._object.unexport();
        this._object = null;
    }
}
