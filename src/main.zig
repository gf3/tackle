const adw = @import("adw");
const build_options = @import("build_options");
const gio = @import("gio");
const glib = @import("glib");
const gobject = @import("gobject");
const gdk = @import("gdk");
const gtk = @import("gtk");
const intl = @import("libintl");
const std = @import("std");
const ulid = @import("ulid.zig");

const allocator = std.heap.page_allocator;

pub const application_id = "com.heavy.Tackle";
const package = "tackle";

pub fn main() !void {
    intl.bindTextDomain(package, build_options.locale_dir ++ "");
    intl.bindTextDomainCodeset(package, "UTF-8");
    intl.setTextDomain(package);

    const app = Application.new();
    const status = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
    std.process.exit(@intCast(status));
}

const Application = extern struct {
    parent_instance: Parent,

    pub const Parent = adw.Application;

    pub const getGObjectType = gobject.ext.defineClass(Application, .{
        .name = "TackleApplication",
        .classInit = &Class.init,
    });

    pub fn new() *Application {
        return gobject.ext.newInstance(Application, .{
            .application_id = application_id,
            .flags = gio.ApplicationFlags{},
        });
    }

    pub fn as(app: *Application, comptime T: type) *T {
        return gobject.ext.as(T, app);
    }

    fn activateImpl(app: *Application) callconv(.C) void {
        const win = ApplicationWindow.new(app);
        gtk.Window.present(win.as(gtk.Window));
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = Application;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.C) void {
            gio.Application.virtual_methods.activate.implement(class, &Application.activateImpl);
        }
    };
};

const ApplicationWindow = extern struct {
    parent_instance: Parent,

    pub const Parent = adw.ApplicationWindow;

    const Private = struct {
        copy_button: *gtk.Button,
        created_label: *gtk.Label,
        input_text: *gtk.TextView,
        output_text: *gtk.TextView,
        toast_overlay: *adw.ToastOverlay,
        translate_button: *gtk.Button,
        window_title: *adw.WindowTitle,

        var offset: c_int = 0;
    };

    pub const getGObjectType = gobject.ext.defineClass(ApplicationWindow, .{
        .name = "TackleApplicationWindow",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    pub fn new(app: *Application) *ApplicationWindow {
        return gobject.ext.newInstance(ApplicationWindow, .{ .application = app });
    }

    pub fn as(win: *ApplicationWindow, comptime T: type) *T {
        return gobject.ext.as(T, win);
    }

    fn init(win: *ApplicationWindow, _: *Class) callconv(.C) void {
        gtk.Widget.initTemplate(win.as(gtk.Widget));

        _ = gtk.Button.signals.clicked.connect(win.private().copy_button, *ApplicationWindow, &handleCopyButtonClicked, win, .{});
        _ = gtk.Button.signals.clicked.connect(win.private().translate_button, *ApplicationWindow, &handleTranslateButtonClicked, win, .{});
    }

    fn dispose(win: *ApplicationWindow) callconv(.C) void {
        gtk.Widget.disposeTemplate(win.as(gtk.Widget), getGObjectType());
        // gobject.Object.virtual_methods.dispose.call(Class.parent, win.as(Parent));
    }

    fn finalize(_: *ApplicationWindow) callconv(.C) void {
        // gobject.Object.virtual_methods.finalize.call(Class.parent, win.as(Parent));
    }

    fn private(win: *ApplicationWindow) *Private {
        return gobject.ext.impl_helpers.getPrivate(win, Private, Private.offset);
    }

    fn handleTranslateButtonClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        resetUI(win);

        const buffer = win.private().input_text.getBuffer();

        var start: gtk.TextIter = undefined;
        var end: gtk.TextIter = undefined;
        gtk.TextBuffer.getBounds(buffer, &start, &end);

        const text = buffer.getText(&start, &end, @intCast(0));
        defer glib.free(text);

        const result = ulid.decode(std.mem.span(text)) catch |err| switch (err) {
            ulid.Error.InvalidCharacter => {
                adw.ToastOverlay.addToast(win.private().toast_overlay, adw.Toast.new(intl.gettext("Invalid character")));
                return;
            },
            ulid.Error.InvalidLength => {
                adw.ToastOverlay.addToast(win.private().toast_overlay, adw.Toast.new(intl.gettext("Invalid length")));
                return;
            },
            else => return,
        };

        const uuid = result.uuid_str(allocator) catch |err| {
            std.debug.print("error building ulid uuid_str: {}\n", .{err});
            adw.ToastOverlay.addToast(win.private().toast_overlay, adw.Toast.new(intl.gettext("Unable to build UUID")));
            return;
        };
        defer allocator.free(uuid);

        const output_buffer = win.private().output_text.getBuffer();
        output_buffer.setText(uuid, @intCast(36));

        const copy_button = win.private().copy_button;
        gtk.Widget.setSensitive(copy_button.as(gtk.Widget), @intFromBool(true));

        const time_str = result.time_str(allocator) catch |err| {
            std.debug.print("error building ulid time_str: {}\n", .{err});
            return;
        };

        const created_label = win.private().created_label;
        created_label.setLabel(time_str.ptr);
        gtk.Widget.setVisible(created_label.as(gtk.Widget), @intFromBool(true));
    }

    fn handleCopyButtonClicked(_: *gtk.Button, win: *ApplicationWindow) callconv(.C) void {
        const buffer = win.private().output_text.getBuffer();

        var start: gtk.TextIter = undefined;
        var end: gtk.TextIter = undefined;

        gtk.TextBuffer.getBounds(buffer, &start, &end);

        const text = buffer.getText(&start, &end, @intCast(0));
        defer glib.free(text);

        if (start.equal(&end) == 1) {
            return;
        }

        if (gdk.Display.getDefault()) |display| {
            display.getClipboard().setText(text);
            adw.ToastOverlay.addToast(win.private().toast_overlay, adw.Toast.new(intl.gettext("Copied to clipboard")));
            return;
        }
    }

    fn resetUI(win: *ApplicationWindow) void {
        const buffer = win.private().output_text.getBuffer();
        buffer.setText("", 0);

        const copy_button = win.private().copy_button.as(gtk.Widget);
        gtk.Widget.setSensitive(copy_button, @intFromBool(false));

        const created_label = win.private().created_label.as(gtk.Widget);
        gtk.Widget.setVisible(created_label, @intFromBool(false));
    }

    pub const Class = extern struct {
        parent_class: Parent.Class,

        var parent: *Parent.Class = undefined;

        pub const Instance = ApplicationWindow;

        pub fn as(class: *Class, comptime T: type) *T {
            return gobject.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.C) void {
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
            gobject.Object.virtual_methods.finalize.implement(class, &finalize);
            gtk.Widget.Class.setTemplateFromResource(class.as(gtk.Widget.Class), "/com/heavy/Tackle/ui/window.ui");
            class.bindTemplateChildPrivate("copy_button", .{});
            class.bindTemplateChildPrivate("created_label", .{});
            class.bindTemplateChildPrivate("input_text", .{});
            class.bindTemplateChildPrivate("output_text", .{});
            class.bindTemplateChildPrivate("toast_overlay", .{});
            class.bindTemplateChildPrivate("translate_button", .{});
            class.bindTemplateChildPrivate("window_title", .{});
        }

        fn bindTemplateChildPrivate(class: *Class, comptime name: [:0]const u8, comptime options: gtk.ext.BindTemplateChildOptions) void {
            gtk.ext.impl_helpers.bindTemplateChildPrivate(class, name, Private, Private.offset, options);
        }
    };
};
