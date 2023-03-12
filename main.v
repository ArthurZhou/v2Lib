import vweb
import os
import markdown
import encoding.utf8
import regex
import json

struct App {
	vweb.Context
}

struct MDData {
	title string
}

__global (
	home = "main.md"
	storage = "docs"
	assets = "assets"
	host = 'localhost'
	port = 8099
	root = os.getwd()
)

fn main() {
	vweb.run_at(&App{}, vweb.RunParams{
		host: host
		port: port
		family: .ip
	}) or { panic(err) }
}

fn getpath(abs_path string) string {
	return root + "/" + storage + "/" + abs_path
}

["/"]
fn (mut app App) root(path string) vweb.Result {
	return app.redirect("/docs/$home")
}

["/assets/:path"]
fn (mut app App) assets(path string) vweb.Result {
	return app.file("$root/$assets/$path")
}

["/docs/:path"]
fn (mut app App) doc(path string) vweb.Result {
	mut page_title := path
	if path[utf8.len(path)-3..utf8.len(path)] == ".md" {
		mut data := os.read_file(getpath(path)) or {
			println(err)
			return app.text("Cannot open file: $path")
		}
		if data.contains("<d2lib>") && data.contains("</d2lib>") {
			re := regex.regex_opt("<d2lib>(.*)</d2lib>") or { panic(err) }
			start, end := re.match_string(data)
			page_data := json.decode(MDData, data[start+7..end-8]) or { panic(err) }
			if page_data.title != "" {
				page_title = page_data.title
			}
			data = data.replace(data[start+7..end-8], "").replace("<d2lib>", "").replace("</d2lib>", "")
		}
		template := os.read_file("$root/$assets/index.html") or {
			println(err)
			return app.text("Cannot load assets")
		}
		return app.html(template.replace("{{ CONTENT }}", markdown.to_html(data)).replace("{{ TITLE }}", page_title))

	} else {
		return app.file(getpath(path))
	}
}