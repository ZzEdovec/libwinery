/* runners.vala
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
    public struct LaunchSpec {
        public Gee.ArrayList<string> argv;
        public Gee.HashMap<string, string>? environ;
    }

    public enum RunnerStatus {
        NOT_INSTALLED,
        DOWNLOADING,
        UNPACKING,
        INSTALLED
    }

    public class RunnerInfo : Object {
        public string name { get; private construct; }
        public Type runner_type { get; private construct; }
        public File install_directory { get; private set; }
        public RunnerStatus status { get; private set; }
        public string? download_url { get; private construct; }

        public signal void download_progress (RunnerStatus status, double progress);

        public RunnerInfo (string name, Type type, string? dn_url = null, File? i_dir = null, RunnerStatus status = RunnerStatus.NOT_INSTALLED) {
            Object (
                name: name,
                runner_type: type,
                install_directory: i_dir ?? Utils.get_app_data_dir ().get_child ("Runners"),
                status: status,
                download_url: dn_url
            );
        }

        public async Runner download (Cancellable? cancellable = null) throws GLib.Error {
            if (!runner_type.is_a (typeof (Runner)))
                throw new Error.RUNNER_TYPE_IS_NOT_A_RUNNER ("Runner type is not a Runner interface");

            if (status != RunnerStatus.NOT_INSTALLED && status != RunnerStatus.INSTALLED)
                throw new IOError.BUSY ("Already downloading");
            else if (status == RunnerStatus.INSTALLED) {
                var runner_obj = get_runner ();
                if (runner_obj == null)
                    throw new Error.RUNNER_TYPE_IS_NOT_A_RUNNER ("Runner type is not a Runner interface");

                return runner_obj;
            }

            if (download_url == null)
                throw new Error.NO_DOWNLOAD_URL ("No download URL");

            var client = new Soup.Session ();
            var msg = new Soup.Message ("GET", download_url);

            var stream = yield client.send_async (msg, Priority.DEFAULT, cancellable);
            if (msg.status_code != Soup.Status.OK)
                throw new IOError.NOT_CONNECTED (@"Status code is not 200: $(msg.status_code)");

            if (!install_directory.query_exists (cancellable))
                install_directory.make_directory_with_parents (cancellable);

            FileIOStream file_stream;
            var archive = yield File.new_tmp_async (null, Priority.DEFAULT, cancellable, out file_stream);

            File? extracted_dir = null;
            GLib.Error? error = null;

            try {
                uint8[] dn_buf = new uint8[16384];
                int64 content_length = msg.response_headers.get_content_length ();
                ssize_t total_readed = 0;
                ssize_t readed = 0;
                while ((readed = yield stream.read_async (dn_buf, Priority.DEFAULT, cancellable)) > 0) {
                    yield file_stream.output_stream.write_all_async (dn_buf[0 : readed], Priority.DEFAULT, cancellable, null);
                    total_readed += readed;

                    status = RunnerStatus.DOWNLOADING;
                    download_progress (
                        RunnerStatus.DOWNLOADING,
                        content_length > 0 ? (total_readed / content_length) * 100 : -1
                    );
                }

                status = RunnerStatus.UNPACKING;
                download_progress (RunnerStatus.UNPACKING, -1);

                var extr_thread = new Thread<File?> (null, () => {
                    var file = extract (archive, cancellable);
                    Idle.add_once (() => { download.callback (); });
                    return file;
                });

                yield;
                extracted_dir = extr_thread.join ();
                if (extracted_dir == null)
                    throw new Error.UNPACK_FAILED ((cancellable != null && cancellable.is_cancelled ()) ? "Cancelled" : "Failed to extract runner");

                install_directory = extracted_dir;

                status = RunnerStatus.INSTALLED;
                download_progress (RunnerStatus.INSTALLED, 100);
            }
            catch (GLib.Error e) {
                error = e;
            }

            yield archive.delete_async (Priority.DEFAULT, cancellable);
            if (error != null)
                throw error;

            return (Runner) Object.new (
                runner_type,
                "name", name,
                "path", extracted_dir,
                "is-system-installation", false
            );
        }

        private File? extract (File archive, Cancellable? cancellable = null) {
            var arc_reader = new Archive.Read ();
            arc_reader.support_format_all ();
            arc_reader.support_filter_all ();
            if (arc_reader.open_filename (archive.get_path (), 10240) != Archive.Result.OK)
                return null;

            unowned Archive.Entry entry;
            Archive.Result last_result;
            string? first_entry_name = null;
            while ((last_result = arc_reader.next_header (out entry)) == Archive.Result.OK) {
                if ((cancellable != null && cancellable.is_cancelled ()) || (first_entry_name == null && entry.filetype () != Archive.FileType.IFDIR))
                    return null;

                if (first_entry_name == null)
                    first_entry_name = entry.pathname ();

                entry.set_pathname (Path.build_filename (install_directory.get_path (), entry.pathname ()));
                if (arc_reader.extract (entry, Archive.ExtractFlags.SECURE_SYMLINKS | Archive.ExtractFlags.SECURE_NODOTDOT | Archive.ExtractFlags.PERM) != Archive.Result.OK)
                    return null;
            }
            if (last_result != Archive.Result.OK)
                return null;

            return install_directory.get_child (first_entry_name);
        }

        public Runner? get_runner () {
            if (!runner_type.is_a (typeof (Runner)) || status != RunnerStatus.INSTALLED)
                return null;

            return (Runner) Object.new (
                runner_type,
                "name", name,
                "path", install_directory,
                "is-system-installation", !install_directory.get_path ().contains (Environment.get_home_dir ())
            );
        }
    }

    public abstract class Runner : Object {
        private File? _path;
        public string name { get; protected construct; }
        public File? path {
            get { return _path; }
            internal set {
                _path = value;
                notify_property ("is-installed");
            }
        }
        public bool is_system_installation { get; protected construct; }
        public bool is_installed { get { return path != null || is_system_installation; } }

        public abstract LaunchSpec? get_launch_spec ();

        public virtual async void @delete (Cancellable? cancellable = null) throws GLib.Error {
            if (!is_installed)
                throw new Error.RUNNER_NOT_INSTALLED ("Runner not installed");
            if (is_system_installation)
                throw new Error.RUNNER_INSTALLED_SYSTEMWIDE ("Runner is systemwide installed");

            if (path.query_exists (cancellable))
                yield delete_recursive (path, cancellable);

            path = null;
        }

        private async void delete_recursive (File path, Cancellable? cancellable) throws GLib.Error {
            var enumer = yield path.enumerate_children_async (
                "%s,%s".printf (FileAttribute.STANDARD_NAME, FileAttribute.STANDARD_TYPE),
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
                Priority.DEFAULT,
                cancellable
            );

            FileInfo? f_info = null;
            while ((f_info = enumer.next_file (cancellable)) != null) {
                var file = path.get_child (f_info.get_name ());
                if (f_info.get_file_type () == FileType.DIRECTORY)
                    yield delete_recursive (file, cancellable);
                else
                    yield file.delete_async (Priority.DEFAULT, cancellable);
            }

            yield path.delete_async (Priority.DEFAULT, cancellable);
        }
    }

    public interface IWine : Runner {
        public abstract File get_wine_path () throws GLib.Error;
        public abstract File get_wineserver_path () throws GLib.Error;
    }

    public class Wine : IWine, Runner {
        public Wine (string name, bool is_sys_install, File? path = null) {
            Object (
                name: name,
                path: path,
                is_system_installation: is_sys_install
            );
        }

        public static Wine? get_system_wine () {
            string? wine_path = Environment.find_program_in_path ("wine");
            if (wine_path == null)
                return null;

            return new Wine ("System Wine", true);
        }

        public override LaunchSpec? get_launch_spec () {
            string? wine_path = null;
            if (path != null) {
                var wine_file = path.get_child ("bin").get_child ("wine");
                if (!wine_file.query_exists ())
                    return null;

                wine_path = wine_file.get_path ();
            }
            else if (is_system_installation) {
                wine_path = Environment.find_program_in_path ("wine");
                if (wine_path == null)
                    return null;
            }

            var argv = new Gee.ArrayList<string> ();
            argv.add (wine_path);
            return { argv, null };
        }

        public File get_wine_path () throws GLib.Error {
            return File.new_for_path (get_launch_spec ().argv[0]);
        }

        public File get_wineserver_path () throws GLib.Error {
            var spec = get_launch_spec ();
            spec.argv[0] += "server";

            return File.new_for_path (spec.argv[0]);
        }
    }

    public class Proton : IWine, Runner {
        public Proton (string name, File path, bool is_sys_install) {
            Object (
                name: name,
                path: path,
                is_system_installation: is_sys_install
            );
        }

        public override LaunchSpec? get_launch_spec () {
            string umu_path = Environment.find_program_in_path ("umu-run");
            string p_path = path.get_path ();
            if (umu_path == null)
                return null;

            var env = new Gee.HashMap<string, string> ();
            env["PROTONPATH"] = p_path;
            var argv = new Gee.ArrayList<string> ();
            argv.add (umu_path);

            return { argv, env };
        }

        public File get_wine_path () throws GLib.Error {
            var wine_path = path.get_child ("files").get_child ("bin").get_child ("wine");
            if (!wine_path.query_exists ())
                throw new IOError.NOT_FOUND ("Not found");

            return wine_path;
        }

        public File get_wineserver_path () throws GLib.Error {
            return File.new_for_path (get_wine_path ().get_path () + "server");
        }
    }
}
