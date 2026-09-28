/* registry.vala
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
    namespace RegistryType {
        public const string SZ = "REG_SZ";
        public const string EXPAND_SZ = "REG_EXPAND_SZ";
        public const string BINARY = "REG_BINARY";
        public const string DWORD = "REG_DWORD";
        public const string QWORD = "REG_QWORD";
        public const string MULTI_SZ = "REG_MULTI_SZ";
    }

    public class RegistryKey : Object {
        public string name { get; private construct; }
        public string registry_type { get; private construct; }
        private Value? value = null;

        private RegistryKey () {}

        public RegistryKey.sz (string name, string? str = null) {
            Object (
                name: name,
                registry_type: RegistryType.SZ
            );

            if (str != null)
                set_sz (str);
        }

        public RegistryKey.multi_sz (string name, Gee.ArrayList<string>? lines = null) {
            Object (
                name: name,
                registry_type: RegistryType.MULTI_SZ
            );

            if (lines != null)
                set_multi_sz (lines);
        }

        public RegistryKey.dword (string name, uint? i = null) {
            Object (
                name: name,
                registry_type: RegistryType.DWORD
            );

            if (i != null)
                set_dword (i);
        }

        public RegistryKey.qword (string name, uint64? i = null) {
            Object (
                name: name,
                registry_type: RegistryType.QWORD
            );

            if (i != null)
                set_qword (i);
        }

        internal static RegistryKey? from_string (string str) {
            string[] params = str.split ("    ", 3);
            if (params.length < 2)
                return null;

            uint last_i = params.length - 1;
            params[last_i] = params[last_i].strip (); // cutting off \r

            switch (params[1]) {
                case (RegistryType.SZ):
                    if (params.length == 3 && params[2] != "(null)")
                        return new RegistryKey.sz (params[0], params[2]);
                    else
                        return new RegistryKey.sz (params[0]);
                case (RegistryType.MULTI_SZ):
                    if (params.length == 3 && params[2] != "(null)") {
                        var lines = new Gee.ArrayList<string> ();
                        lines.add_all_array (params[2].split ("\\0"));

                        return new RegistryKey.multi_sz (params[0], lines);
                    }
                    else
                        return new RegistryKey.multi_sz (params[0]);
                case (RegistryType.DWORD):
                    uint? parsed_uint = null;
                    if (params.length == 3 && params[2] != "(null)" && params[2].has_prefix ("0x") && uint.try_parse (params[2][2:], out parsed_uint))
                        return new RegistryKey.dword (params[0], parsed_uint);
                    else
                        return new RegistryKey.dword (params[0]);
                case (RegistryType.QWORD):
                    uint64? parsed_uint = null;
                    if (params.length == 3 && params[2] != "(null)" && params[2].has_prefix ("0x") && uint64.try_parse (params[2][2:], out parsed_uint))
                        return new RegistryKey.qword (params[0], parsed_uint);
                    else
                        return new RegistryKey.qword (params[0]);
                default:
                    return null;
            }
        }

        public string? get_value_as_string () {
            if (value == null)
                return null;

            switch (registry_type) {
                case (RegistryType.SZ):
                    return value.dup_string ();
                case (RegistryType.MULTI_SZ):
                    return string.joinv ("\\0", get_multi_sz ().to_array ());
                case (RegistryType.DWORD):
                    return value.get_uint ().to_string ();
                case (RegistryType.QWORD):
                    return value.get_uint64 ().to_string ();
                default:
                    return null;
            }
        }

        public unowned string? get_sz () {
            if (value == null)
                return null;

            return value.get_string ();
        }

        public unowned Gee.ArrayList<string>? get_multi_sz () {
            if (value == null)
                return null;

            return value.get_object () as Gee.ArrayList<string>;
        }

        public uint? get_dword () {
            if (value == null)
                return null;

            return value.get_uint ();
        }

        public uint64? get_qword () {
            if (value == null)
                return null;

            return value.get_uint64 ();
        }

        public bool set_sz (string str) {
            if (value == null)
                value = Value (typeof (string));
            else if (!value.holds (typeof (string)))
                return false;

            value.set_string (str);
            return true;
        }

        public bool set_multi_sz (Gee.ArrayList<string> lines) {
            if (value == null)
                value = Value (typeof (Gee.ArrayList));
            else if (!value.holds (typeof (Gee.ArrayList)))
                return false;

            value.set_object (lines);
            return true;
        }

        public bool set_dword (uint i) {
            if (value == null)
                value = Value (typeof (uint));
            else if (!value.holds (typeof (uint)))
                return false;

            value.set_uint (i);
            return true;
        }

        public bool set_qword (uint64 i) {
            if (value == null)
                value = Value (typeof (uint64));
            else if (!value.holds (typeof (uint64)))
                return false;

            value.set_uint64 (i);
            return true;
        }
    }

    public class RegistrySection : Object {
        public string path { get; private construct; }
        public Gee.ArrayList<RegistryKey> keys { get; default = new Gee.ArrayList<RegistryKey> (); }

        private RegistrySection (string path) {
            Object (path: path);
        }

        internal static Gee.ArrayList<RegistrySection> from_string (string str) {
            var sections = new Gee.ArrayList<RegistrySection> ();
            string[] lines = str.split ("\n");

            RegistrySection? current_section = null;
            foreach (string line in lines) {
                if (line == "\r" || line == "") {
                    if (current_section != null) {
                        sections.add (current_section);
                        current_section = null;
                    }

                    continue;
                }

                if (line.has_prefix ("HKEY_")) {
                    if (current_section != null)
                        sections.add (current_section);

                    current_section = new RegistrySection (line.strip ()); // cutting off \r
                    continue;
                }

                if (current_section != null && line.has_prefix ("    ")) {
                    var key = RegistryKey.from_string (line);
                    if (key == null)
                        continue;

                    current_section.keys.add (key);
                }
            }

            if (current_section != null)
                sections.add (current_section);

            return sections;
        }
    }

    public class Registry : Object {
        public Prefix prefix { get; set; }

        public Registry (Prefix prefix) {
            Object (prefix: prefix);
        }

        public async Gee.ArrayList<RegistrySection> query (string path, bool recursive = false, bool with_default = false, Cancellable? cancellable = null) throws GLib.Error {
            string[] argv = { "reg", "query", path };
            if (recursive)
                argv += "/s";
            if (with_default)
                argv += "/ve";

            var env = new Gee.HashMap<string, string> ();
            env["LC_ALL"] = "C";

            var proc = prefix.execute_wine (argv, SubprocessFlags.STDOUT_PIPE, env);
            string? stdout;
            yield proc.communicate_utf8_async (null, cancellable, out stdout, null);

            return RegistrySection.from_string (stdout);
        }

        public async bool add_section (string path, Cancellable? cancellable = null) throws GLib.Error {
            var proc = prefix.execute_wine ({ "reg", "add", path, "/f" });
            return yield proc.wait_check_async (cancellable);
        }

        public async bool add_key (string section, RegistryKey key, Cancellable? cancellable = null) throws GLib.Error {
            string? data = key.get_value_as_string ();
            if (data == null)
                return false;

            var proc = prefix.execute_wine ({ "reg", "add", section, "/f", "/d", data, "/t", key.registry_type, "/v", key.name });
            return yield proc.wait_check_async (cancellable);
        }

        private async bool set_default_key (string section, string data, string type, Cancellable? cancellable) throws GLib.Error {
            var proc = prefix.execute_wine ({ "reg", "add", section, "/f", "/d", data, "/t", type, "/ve" });
            return yield proc.wait_check_async (cancellable);
        }

        public async bool set_default_sz (string section, string str, Cancellable? cancellable = null) throws GLib.Error {
            return yield set_default_key (section, str, RegistryType.SZ, cancellable);
        }

        public async bool set_default_multi_sz (string section, Gee.ArrayList<string> lines, Cancellable? cancellable = null) throws GLib.Error {
            return yield set_default_key (section, string.joinv ("\\0", lines.to_array ()), RegistryType.MULTI_SZ, cancellable);
        }

        public async bool set_default_dword (string section, uint i, Cancellable? cancellable = null) throws GLib.Error {
            return yield set_default_key (section, i.to_string (), RegistryType.DWORD, cancellable);
        }

        public async bool set_default_qword (string section, uint64 i, Cancellable? cancellable = null) throws GLib.Error {
            return yield set_default_key (section, i.to_string (), RegistryType.QWORD, cancellable);
        }

        public async bool copy (string section1, string section2, bool recursive = false, Cancellable? cancellable = null) throws GLib.Error {
            string[] argv = { "reg", "copy", section1, section2, "/f" };
            if (recursive)
                argv += "/s";

            var proc = prefix.execute_wine (argv);
            return yield proc.wait_check_async (cancellable);
        }

        public async bool delete_section (string section, Cancellable? cancellable = null) throws GLib.Error {
            var proc = prefix.execute_wine ({ "reg", "delete", section, "/f" });
            return yield proc.wait_check_async (cancellable);
        }

        public async bool clear_section (string section, Cancellable? cancellable = null) throws GLib.Error {
            var proc = prefix.execute_wine ({ "reg", "delete", section, "/va", "/f" });
            return yield proc.wait_check_async (cancellable);
        }

        public async bool delete_default_key (string section, Cancellable? cancellable = null) throws GLib.Error {
            var proc = prefix.execute_wine ({ "reg", "delete", section, "/ve", "/f" });
            return yield proc.wait_check_async (cancellable);
        }

        public async bool delete_key (string section, string key_name, Cancellable? cancellable = null) throws GLib.Error {
            var proc = prefix.execute_wine ({ "reg", "delete", section, "/v", key_name, "/f" });
            return yield proc.wait_check_async (cancellable);
        }
    }
}
