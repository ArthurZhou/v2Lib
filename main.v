import vweb
import os
import markdown
import encoding.utf8
import regex
import json
import log
import time

struct App {
	vweb.Context
}

struct MDData {
	title string
}

struct Config {
	host string
	port int
	home string
	storage string
	assets string
	log_to_file bool
	log_level string
}

__global (
	ver = "0.0.2-s20220313"
	l log.Log
	root = os.getwd()
)

fn read_config() {
	if !os.exists("$root/config.json") {
		os.create("$root/config.json") or {
			l.error(err.str())
		}
	}
	cfg := os.read_file("$root/config.json") or {
		l.fatal(err.str())
	}
	cfg_data := json.decode(Config, cfg) or {
		l.fatal(err.str())
	}
	os.setenv("HOST", cfg_data.host, false)
	os.setenv("PORT", cfg_data.port.str(), false)
	os.setenv("HOME", cfg_data.home, true)
	os.setenv("STORAGE", cfg_data.storage, true)
	os.setenv("ASSETS", cfg_data.assets, true)

	if cfg_data.log_to_file {
		if !os.exists("$root/logs") {
			os.mkdir("$root/logs", os.MkdirParams{mode: 0o777}) or {
				l.fatal(err.str())
			}
		}
		os.create("$root/logs/${time.now().str().replace(" ", "=").replace(":", "-")}.log") or {
			l.fatal(err.str())
		}
		l.set_full_logpath("$root/logs/${time.now().str().replace(" ", "=").replace(":", "-")}.log")
		l.log_to_console_too()
	}
	l.set_level(log.level_from_tag(cfg_data.log_level) or {
		l.warn("Invalid log level: ${cfg_data.log_level}")
		log.Level.debug
	})
}

fn main() {
	println('                     
     ___ __    _ _   
 _ _|_  |  |  |_| |_ 
| | |  _|  |__| | . |
 \\_/|___|_____|_|___|
                     ')
	l.set_level(.debug)
	l.info("Starting v2Lib  version:$ver")
	os.setenv("ROOT", os.getwd(), false)
	read_config()
	vweb.run_at(&App{}, vweb.RunParams{
		host: os.getenv("HOST")
		port: os.getenv("PORT").int()
		family: .ip
	}) or { l.fatal(err.str()) }
}

fn getpath(abs_path string) string {
	return "$root/${os.getenv("STORAGE")}/$abs_path"
}

["/"]
fn (mut app App) index() vweb.Result {
	return app.redirect("/docs/${os.getenv("HOME")}")
}

["/assets/:path"]
fn (mut app App) assets(path string) vweb.Result {
	return app.file("$root/${os.getenv("ASSETS")}/$path")
}

["/docs/:path"]
fn (mut app App) doc(path string) vweb.Result {
	mut page_title := path
	if path[utf8.len(path)-3..utf8.len(path)] == ".md" {
		mut data := os.read_file(getpath(path)) or {
			l.error(err.str())
			return app.text("Cannot open file: $path")
		}
		if data.contains("<d2lib>") && data.contains("</d2lib>") {
			re := regex.regex_opt("<d2lib>(.*)</d2lib>") or { l.fatal(err.str()) }
			start, end := re.match_string(data)
			page_data := json.decode(MDData, data[start+7..end-8]) or { l.fatal(err.str()) }
			if page_data.title != "" {
				page_title = page_data.title
			}
			data = data.replace(data[start+7..end-8], "").replace("<d2lib>", "").replace("</d2lib>", "")
		}
		template := os.read_file("$root/${os.getenv("ASSETS")}/index.html") or {
			l.error(err.str())
			return app.text("Cannot load assets")
		}
		return app.html(template.replace("{{ CONTENT }}", markdown.to_html(data)).replace("{{ TITLE }}", page_title))

	} else {
		return app.file(getpath(path))
	}
}