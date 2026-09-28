/* repos.vala
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
    public abstract class Source : Object {
        public bool is_local { get; protected construct; }

        public abstract async Gee.ArrayList<RunnerInfo> query (Cancellable? cancellable = null) throws GLib.Error;
    }

    public class GEProtonSource : Source {
        public GEProtonSource () {
            Object (is_local: false);
        }

        public override async Gee.ArrayList<RunnerInfo> query (Cancellable? cancellable = null) throws GLib.Error {
            var releases = yield GitHub.fetch_releases ("gloriouseggroll/proton-ge-custom", cancellable);
            var runners = new Gee.ArrayList<RunnerInfo> ();

            foreach (var release in releases) {
                foreach (var asset in release.assets) {
                    if (asset.content_type != "application/gzip" || !asset.browser_download_url.has_suffix (".tar.gz") || asset.name.contains ("aarch64"))
                        continue;

                    runners.add (new RunnerInfo (
                        release.tag_name,
                        typeof (Proton),
                        asset.browser_download_url
                    ));
                }
            }

            return runners;
        }
    }

    public class LocalSource : Source {
        public File directory { get; private construct; }

        public LocalSource (File? directory = null) {
            Object (
                is_local: true,
                directory: directory ?? Utils.get_app_data_dir ().get_child ("Runners")
            );
        }

        public override async Gee.ArrayList<RunnerInfo> query (Cancellable? cancellable = null) throws GLib.Error {
            var enumer = yield directory.enumerate_children_async (
                "%s,%s".printf (FileAttribute.STANDARD_NAME, FileAttribute.STANDARD_TYPE),
                FileQueryInfoFlags.NONE,
                Priority.DEFAULT,
                cancellable
            );

            var runners = new Gee.ArrayList<RunnerInfo> ();
            FileInfo? f_info = null;
            while ((f_info = enumer.next_file (cancellable)) != null) {
                if (f_info.get_file_type () != FileType.DIRECTORY)
                    continue;

                var runner_dir = directory.get_child (f_info.get_name ());
                var version_file = runner_dir.get_child ("version");
                var wine_bin = runner_dir.get_child ("bin").get_child ("wine");
                if (runner_dir.get_child ("proton").query_exists (cancellable) && version_file.query_exists (cancellable)) {
                    var stream = FileStream.open (version_file.get_path (), "r");
                    string? ver_line = stream.read_line ();

                    if (ver_line == null)
                        continue;

                    int space_pos = ver_line.index_of_char (' ');
                    if (space_pos == -1)
                        continue;

                    runners.add (new RunnerInfo (
                        ver_line[space_pos + 1 :],
                        typeof (Proton),
                        null,
                        runner_dir,
                        RunnerStatus.INSTALLED
                    ));
                }
                else if (wine_bin.query_exists (cancellable)) {
                    var process = new Subprocess (SubprocessFlags.STDOUT_PIPE, wine_bin.get_path (), "--version");
                    string? stdout = null;
                    yield process.communicate_utf8_async (null, cancellable, out stdout, null);

                    if (stdout != null)
                        runners.add (new RunnerInfo (
                            stdout.strip (),
                            typeof (Wine),
                            null,
                            runner_dir,
                            RunnerStatus.INSTALLED
                        ));
                }
            }

            return runners;
        }
    }

    public class Repository : Object {
        private static Gee.ArrayList<Source> default_sources;
        public Gee.ArrayList<Source> sources { get; default = new Gee.ArrayList<Source> (); }

        static construct {
            default_sources = new Gee.ArrayList<Source> ();

            var steam_user_compat = File.new_build_filename (Environment.get_user_data_dir (), "Steam", "compatibilitytools.d");
            if (steam_user_compat.query_exists ())
                default_sources.add (new LocalSource (steam_user_compat));
            var steam_sys_compat = File.new_build_filename ("/", "usr", "share", "steam", "compatibilitytools.d");
            if (steam_sys_compat.query_exists ())
                default_sources.add (new LocalSource (steam_sys_compat));

            default_sources.add_all_array ({ new LocalSource (), new GEProtonSource () });
        }

        public void add_source (Source src) {
            sources.add (src);
        }

        public static async Gee.ArrayList<RunnerInfo> query_default (Cancellable? cancellable = null, out Gee.HashMap<Source, GLib.Error> errors) {
            var runners = new Gee.ArrayList<RunnerInfo> ();
            errors = new Gee.HashMap<Source, GLib.Error> ();
            foreach (var source in default_sources) {
                try { runners.add_all (yield source.query (cancellable)); }
                catch (GLib.Error e) { errors[source] = e; }
            }

            return runners;
        }

        public async Gee.ArrayList<RunnerInfo> query_all (bool include_default = true, Cancellable? cancellable = null, out Gee.HashMap<Source, GLib.Error> errors) {
            Gee.ArrayList<RunnerInfo> runners;
            if (include_default)
                runners = yield query_default (cancellable, out errors);
            else {
                runners = new Gee.ArrayList<RunnerInfo> ();
                errors = new Gee.HashMap<Source, GLib.Error> ();
            }

            foreach (var source in sources) {
                try { runners.add_all (yield source.query (cancellable)); }
                catch (GLib.Error e) { errors[source] = e; }
            }

            return runners;
        }
    }
}
