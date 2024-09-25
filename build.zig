const std = @import("std");
const gobject_build = @import("gobject");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const gobject = b.dependency("gobject", .{});
    const xml = b.dependency("xml", .{}).module("xml");

    const data_dir: std.Build.InstallDir = .{ .custom = "share" };
    const locale_dir: std.Build.InstallDir = .{ .custom = "share/locale" };
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "locale_dir", b.getInstallPath(locale_dir, ""));

    const exe = b.addExecutable(.{
        .name = "tackle",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.root_module.addOptions("build_options", build_options);
    exe.root_module.addImport("xml", xml);
    exe.root_module.addImport("glib", gobject.module("glib2"));
    exe.root_module.addImport("gobject", gobject.module("gobject2"));
    exe.root_module.addImport("gio", gobject.module("gio2"));
    exe.root_module.addImport("gdk", gobject.module("gdk4"));
    exe.root_module.addImport("gtk", gobject.module("gtk4"));
    exe.root_module.addImport("cairo", gobject.module("cairo1"));
    exe.root_module.addImport("pango", gobject.module("pango1"));
    exe.root_module.addImport("pangocairo", gobject.module("pangocairo1"));
    exe.root_module.addImport("adw", gobject.module("adw1"));
    exe.root_module.addImport("libintl", b.dependency("libintl", .{}).module("libintl"));

    const gresources = gobject_build.addCompileResources(b, target, b.path("data/resources/gresources.xml"));
    exe.root_module.addImport("gresources", gresources);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);
    b.installDirectory(.{
        .source_dir = b.path("data/icons"),
        .install_dir = data_dir,
        .install_subdir = "icons",
    });

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    run_cmd.setEnvironmentVariable("XDG_DATA_HOME", b.getInstallPath(data_dir, "."));

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    // Translations
    const run_xgettext = b.addSystemCommand(&.{
        "xgettext",
        "-f",
        b.pathFromRoot(b.pathJoin(&.{ "po", "POTFILES.in" })),
        "-o",
        b.pathFromRoot(b.pathJoin(&.{ "po", "tackle.pot" })),
        "--package-name=Tackle",
        "--package-version=0.0.0", // TODO: use real version once we can import build.zig.zon
        "--copyright-holder=Tackle contributors",
    });

    const xgettext_step = b.step("xgettext", "Generate tackle.pot using xgettext");
    xgettext_step.dependOn(&run_xgettext.step);
}
