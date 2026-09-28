/* prefix.vala
 *
 * Copyright 2026 Kai Neumann <zzedovec@yahoo.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */



namespace Winery {
    namespace DllOverrideType {
        public const string NATIVE = "native";
        public const string BUILTIN = "builtin";
        public const string DISABLED = "";
        public const string NATIVE_BUILTIN = "native,builtin";
        public const string BUILTIN_NATIVE = "builtin,native";
    }

    public class DllOverride : Object {
        public string dll { get; set; }
        public string override_type { get; set; }

        public DllOverride (string dll, string type) {
            Object (
                dll: dll,
                override_type: type
            );
        }
    }

    public class Prefix : Object {
        public IWine runner { get; set; }
        public File path { get; construct; }

        public Prefix (IWine runner, File path) {
            Object (
                runner: runner,
                path: path
            );
        }

        private static void apply_environment (SubprocessLauncher launcher, Gee.HashMap<string, string> environ) {
            foreach (var env in environ)
                launcher.setenv (env.key, env.value, true);
        }

        public Subprocess execute (string[] argv, SubprocessFlags flags = SubprocessFlags.NONE, Gee.HashMap<string, string>? custom_env = null) throws GLib.Error {
            var launch_spec = runner.get_launch_spec ();
            if (launch_spec == null)
                throw new IOError.FAILED ("Failed to get launch spec");

            var launcher = new SubprocessLauncher (flags);

            if (custom_env != null)
                apply_environment (launcher, custom_env);
            if (launch_spec.environ != null)
                apply_environment (launcher, launch_spec.environ);

            launcher.setenv ("WINEPREFIX", path.get_path (), true);

            launch_spec.argv.add_all_array (argv);
            return launcher.spawnv (launch_spec.argv.to_array ());
        }

        public Subprocess execute_wineserver (string[] argv, SubprocessFlags flags = SubprocessFlags.NONE) throws GLib.Error {
            var launcher = new SubprocessLauncher (flags);
            launcher.setenv ("WINEPREFIX", path.get_path (), true);

            var server_argv = new Gee.ArrayList<string> ();
            server_argv.add (runner.get_wineserver_path ().get_path ());
            server_argv.add_all_array (argv);

            return launcher.spawnv (server_argv.to_array ());
        }

        public Subprocess execute_wine (string[] argv, SubprocessFlags flags = SubprocessFlags.NONE, Gee.HashMap<string, string>? custom_env = null) throws GLib.Error {
            var launcher = new SubprocessLauncher (flags);

            if (custom_env != null)
                apply_environment (launcher, custom_env);

            launcher.setenv ("WINEPREFIX", path.get_path (), true);

            var wine_argv = new Gee.ArrayList<string> ();
            wine_argv.add (runner.get_wine_path ().get_path ());
            wine_argv.add_all_array (argv);

            return launcher.spawnv (wine_argv.to_array ());
        }

        public Subprocess execute_winecfg (SubprocessFlags flags = SubprocessFlags.NONE, Gee.HashMap<string, string>? custom_env = null) throws GLib.Error {
            return execute_wine ({ "winecfg" }, flags, custom_env);
        }

        public Subprocess execute_winefile (SubprocessFlags flags = SubprocessFlags.NONE, Gee.HashMap<string, string>? custom_env = null) throws GLib.Error {
            return execute_wine ({ "winefile" }, flags, custom_env);
        }

        public Subprocess execute_explorer (SubprocessFlags flags = SubprocessFlags.NONE, Gee.HashMap<string, string>? custom_env = null) throws GLib.Error {
            return execute_wine ({ "explorer" }, flags, custom_env);
        }

        public Subprocess execute_regedit (SubprocessFlags flags = SubprocessFlags.NONE, Gee.HashMap<string, string>? custom_env = null) throws GLib.Error {
            return execute_wine ({ "regedit" }, flags, custom_env);
        }

        public async void wait_for_exit (Cancellable? cancellable = null) throws GLib.Error {
            yield execute_wineserver ({ "-w" }).wait_async (cancellable);
        }

        public async Gee.ArrayList<DllOverride> get_overrides (Cancellable? cancellable = null) throws GLib.Error {
            var sections = yield new Registry (this).query ("HKCU\\Software\\Wine\\DllOverrides", false, false, cancellable);
            var overrides = new Gee.ArrayList<DllOverride> ();

            foreach (var section in sections) {
                if (section.keys.is_empty)
                    continue;

                foreach (var key in section.keys) {
                    if (key.registry_type != RegistryType.SZ)
                        continue;

                    overrides.add (new DllOverride (key.name, key.get_sz () ?? DllOverrideType.DISABLED));
                }

                break;
            }

            return overrides;
        }

        public async bool set_override (DllOverride override, Cancellable? cancellable = null) throws GLib.Error {
            var key = new RegistryKey.sz (override.dll, override.override_type);
            return yield new Registry (this).add_key ("HKCU\\Software\\Wine\\DllOverrides", key, cancellable);
        }
    }
}
