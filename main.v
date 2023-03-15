import vweb
import os
import markdown
import encoding.utf8
import regex
import json
import log
import time
import net.http

struct App { // main app context
	vweb.Context
}

struct MDData { // markdown extended data structure
	title string
}

struct Config { // config structure
	host string
	port int
	home string
	storage string
	assets string
	log_to_file bool
	log_level string
}
struct AccountData {
	keys []struct {
		name string
		hash string
	}
}

__global ( // global variables(add param -enable-globals when running or building)
	ver = "0.0.2-s20220315" // version
	l log.Log // logger
	root = os.getwd() // root path
	keys AccountData
	accounts []string
)

fn read_config() {
	l.debug("Reading config")
	if !os.exists("$root/config.json") { // if config.json does not exist
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

	if cfg_data.log_to_file { // if log to file is enabled
		if !os.exists("$root/logs") { // if logs folder does not exist
			os.mkdir("$root/logs", os.MkdirParams{mode: 0o777}) or {
				l.fatal(err.str())
			}
		}
		log_name := time.now().str().replace(" ", "=").replace(":", "-") + ".log"
		// log files look like: YYYY-MM-DD=HH-MM-SS.log
		os.create("$root/logs/$log_name") or {
			l.fatal(err.str())
		}
		l.set_full_logpath("$root/logs/$log_name")
		l.log_to_console_too()
		l.warn("Logging to file: $log_name")
	}
	// set log levels: FATAL ERROR WARN INFO DEBUG DISABLED
	l.info("Using log level ${cfg_data.log_level}")
	l.set_level(log.level_from_tag(cfg_data.log_level) or {
		l.warn("Invalid log level: ${cfg_data.log_level}")
		log.Level.info
	})
	l.debug("Config loaded")
}

fn load_keys() {
	l.debug("Loading keys")
	keys = json.decode(AccountData, os.read_file("$root/keys.json") or {
		l.fatal(err.str())
	}) or {
		l.fatal("Error loading keys  reason: ${err.str()}")
	}
	for name in keys.keys {
		accounts << name.name
	}
	l.debug("Keys loaded")
}

fn load_template() {
	l.debug("Loading templates")
	template := os.read_file("$root/${os.getenv("ASSETS")}/index.html") or {
		l.fatal(err.str())
	}
	os.setenv("TEMPLATE", template, true)
	login := os.read_file("$root/${os.getenv("ASSETS")}/login.html") or {
		l.fatal(err.str())
	}
	os.setenv("LOGIN", login, true)
	l.debug("Templates loaded")
}

fn main() {
	println('                     
      ___ __    _ _   
  _ _|_  |  |  |_| |_ 
 | | |  _|  |__| | . |
  \\_/|___|_____|_|___|
 ---------------------
   fast small simple
                     ')
	l.set_level(.debug) // set default logging level
	l.info("Starting v2Lib  version:$ver")
	read_config()
	load_template()
	load_keys()
	l.info("Starting v2Lib server on http://${os.getenv("HOST")}:${os.getenv("PORT")}/")
	vweb.run_at(&App{}, vweb.RunParams{
		host: os.getenv("HOST")
		port: os.getenv("PORT").int()
		family: .ip
		startup_message: false
	}) or {
		l.error(err.str())
	}
}

fn getpath(abs_path string) string {
	return "$root/${os.getenv("STORAGE")}/$abs_path"
}

["/"]
fn (mut app App) index() vweb.Result { // redirect to home page when visiting /
	return app.redirect("/docs/${os.getenv("HOME")}")
}

["/:path"; get]
fn (mut app App) other(_ string) vweb.Result { // response 404 when visiting invalid path
	return app.not_found()
}

["/account/login"; get]
fn (mut app App) login() vweb.Result { // show login page
	return app.html(os.getenv("LOGIN").replace("{{ ERR }}", ""))
}

["/login"; post]
fn (mut app App) handle_login() vweb.Result { // handle login form
	form := app.form.clone()
	account_index := accounts.index(form["name"])
	if account_index >= 0 {
		current_acc := keys.keys[account_index]
		if form["pass"] == current_acc.hash {
			app.set_cookie(http.Cookie{
				name: "account",
				value: current_acc.name,
				path: "/",
			})
			return app.redirect("/docs/${os.getenv("HOME")}")
		} else {
			return app.html(os.getenv("LOGIN").replace("{{ ERR }}", "Wrong username or password"))
		}
	} else {
		return app.html(os.getenv("LOGIN").replace("{{ ERR }}", "Wrong username or password"))
	}
}

["/logout"; post]
fn (mut app App) handle_logout() vweb.Result { // handle login form
	app.set_cookie(http.Cookie{
		name: "account",
		value: "",
		path: "/",
	})
	return app.redirect("/account/login")
}

["/assets/:path"]
fn (mut app App) assets(path string) vweb.Result { // serve assets files
	return app.file("$root/${os.getenv("ASSETS")}/$path")
}

["/docs/:path"]
fn (mut app App) docs(path string) vweb.Result { // serve docs
	if accounts.index(app.get_cookie("account") or {
		return app.redirect("/account/login")
	}) >= 0 {
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

				return app.html(os.getenv("TEMPLATE").replace("{{ CONTENT }}", markdown.to_html(data)).replace("{{ TITLE }}", page_title))

			} else {
				return app.file(getpath(path))
			}
		} else {
			return app.not_found()
		}
	} else {
		return app.redirect("/account/login")
	}
}