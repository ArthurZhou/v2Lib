module core

import os
import markdown
import json
import regex
import encoding.utf8
import vweb
import log

struct MDData { // markdown extended data structure
	title string
}

fn getpath(abs_path string) string {
	return "${os.getenv("ROOT")}/${os.getenv("STORAGE")}/$abs_path"
}

fn render(mut l log.Log, mut app App, path string) vweb.Result {
	mut page_title := path
	if os.exists(getpath(path)) {
		if path[utf8.len(path)-3..utf8.len(path)] == ".md" {
			mut data := os.read_file(getpath(path)) or {
				l.error(err.str())
				return app.text("Cannot open file: $path")
			}
			if data.contains("<d2lib>") && data.contains("</d2lib>") {
				re := regex.regex_opt("<d2lib>(.*)</d2lib>") or {
					l.error("Error loading extended data for `$path` reason: ${err.str()}")
					return app.server_error(500)
				}
				start, end := re.match_string(data)
				page_data := json.decode(MDData, data[start+7..end-8]) or {
					l.error("Error decoding extended data for `$path` reason: ${err.str()}")
					return app.server_error(500)
				}
				if page_data.title != "" {
					page_title = page_data.title
				}
				data = data.replace(data[start+7..end-8], "").replace("<d2lib>", "").replace("</d2lib>", "")
			}

			return app.html(os.getenv("TEMPLATE").replace("{{ CONTENT }}", markdown.to_html(data)).replace("{{ TITLE }}", page_title).replace("{{ MENU }}", os.getenv("MENUBAR")))

		} else {
			return app.file(getpath(path))
		}
	} else {
		return app.not_found()
	}
}
