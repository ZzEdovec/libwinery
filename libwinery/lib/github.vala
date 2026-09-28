/* github.vala
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



namespace Winery.GitHub {
    internal class Asset : Json.Serializable, Object {
        public string name { get; set; }
        public string content_type { get; set; }
        public string state { get; set; }
        public string browser_download_url { get; set; }

        public unowned ParamSpec? find_property (string name) {
            return get_class ().find_property (name.replace ("_", "-"));
        }
    }

    internal class Release : Json.Serializable, Object {
        public string tag_name { get; set; }
        public Gee.ArrayList<Asset> assets { get; set; }

        public unowned ParamSpec? find_property (string name) {
            return get_class ().find_property (name.replace ("_", "-"));
        }

        public bool deserialize_property (string property, out Value val, ParamSpec pspec, Json.Node node) {
            if (property != "assets")
                return default_deserialize_property (property, out val, pspec, node);

            var assets = new Gee.ArrayList<Asset> ();
            val = Value (typeof (Gee.ArrayList));
            val.set_object (assets);

            if (node.get_node_type () != Json.NodeType.ARRAY)
                return false;

            foreach (var element in node.get_array ().get_elements ())
                assets.add ((Asset) Json.gobject_deserialize (typeof (Asset), element));

            return true;
        }
    }

    internal async Gee.ArrayList<Release> fetch_releases (string repo, Cancellable? cancellable = null) throws GLib.Error {
        var session = new Soup.Session ();
        var msg = new Soup.Message ("GET", @"https://api.github.com/repos/$repo/releases");

        Bytes response = yield session.send_and_read_async (msg, Priority.DEFAULT, cancellable);

        if (msg.status_code != 200)
            throw new IOError.FAILED (@"GitHub API returned status code: $(msg.status_code)");

        var parser = new Json.Parser ();
        parser.load_from_data ((string) response.get_data ());

        Json.Node? root = null;
        Json.Array? root_array = null;
        if ((root = parser.get_root ()) == null || (root_array = root.get_array ()) == null)
            throw new Error.FAILED_TO_PARSE ("Failed to parse GitHub Releases API response");

        var releases = new Gee.ArrayList<Release> ();
        foreach (var node in root_array.get_elements ())
            releases.add ((Release) Json.gobject_deserialize (typeof (Release), node));

        return releases;
    }
}
