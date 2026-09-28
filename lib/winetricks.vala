/* winetricks.vala
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
    public class WinetricksVerb : Object {
        public string category { get; private construct; }
        public string name { get; private construct; }
        public string description { get; private construct; }
        public string? status { get; private construct; }

        internal WinetricksVerb (string cat, string name, string desc, string? status) {
            Object (
                category: cat,
                name: name,
                description: desc,
                status: status
            );
        }
    }

    public class Winetricks : Object {
        public Prefix prefix { get; construct; }

        public Winetricks (Prefix prefix) {
            Object (prefix: prefix);
        }

        public async Gee.ArrayList<WinetricksVerb> list_verbs () throws GLib.Error {
            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
            launcher.setenv ("WINEPREFIX", prefix.path.get_path (), true);
            launcher.setenv ("WINE", prefix.runner.get_wine_path ().get_path (), true);

            var pipe = launcher.spawn ("winetricks", "list-all").get_stdout_pipe ();

            var input = new DataInputStream (pipe);
            var regex = new Regex ("^(\\S+)\\s+(.+?)(?:\\s+\\[([^\\]]+)\\])?$", RegexCompileFlags.DEFAULT, RegexMatchFlags.DEFAULT);
            var verbs = new Gee.ArrayList<WinetricksVerb> ();
            string? line;
            string current_category = "";
            while ((line = yield input.read_line_utf8_async (Priority.DEFAULT)) != null) {
                if (line.has_prefix ("=====")) {
                    current_category = line[line.index_of_char (' ', 4) + 1 : line.last_index_of_char (' ')];
                    continue;
                }

                MatchInfo match_info;
                if (!regex.match (line, RegexMatchFlags.DEFAULT, out match_info) || match_info.get_match_count () < 2)
                    continue;

                var verb = new WinetricksVerb (
                    current_category,
                    match_info.fetch (1),
                    match_info.fetch (2),
                    match_info.fetch (3)
                );
                verbs.add (verb);
            }

            return verbs;
        }

        public async bool execute_verbs (string[] verb_names, bool force = false) throws GLib.Error {
            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
            launcher.setenv ("WINEPREFIX", prefix.path.get_path (), true);
            launcher.setenv ("WINE", prefix.runner.get_wine_path ().get_path (), true);

            var argv = new Gee.ArrayList<string> ();
            argv.add_all_array ({ "winetricks", "-q" });
            if (force)
                argv.add ("--force");
            argv.add_all_array (verb_names);

            var proc = launcher.spawnv (argv.to_array ());
            return yield proc.wait_check_async ();
        }
    }
}
