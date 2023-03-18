module core

import os
import vweb
import net.http
import crypto.sha256
import log

struct App { // main app context
	vweb.Context
}

pub fn start(mut l log.Log) {
	vweb.run_at(&App{}, vweb.RunParams{
		host: os.getenv("HOST")
		port: os.getenv("PORT").int()
		family: .ip
		show_startup_message: false
	}) or {
		l.error(err.str())
	}
}

["/"]
pub fn (mut app App) index() vweb.Result { // redirect to home page when visiting /
	return app.redirect("/docs/${os.getenv("HOME")}")
}

["/login"; get]
pub fn (mut app App) login() vweb.Result { // show login page
	if os.getenv("ENABLE_LOGIN") == "true" {
		return app.html(os.getenv("LOGIN").replace("{{ ERR }}", ""))
	} else {
		return app.not_found()
	}
}

["/login"; post]
pub fn (mut app App) handle_login() vweb.Result { // handle login form
	if os.getenv("ENABLE_LOGIN") == "true" {
		form := app.form.clone()
		account_index := accounts.index(form["name"])
		if account_index >= 0 {
			current_acc := keys.keys[account_index]
			if sha256.hexhash(form["pass"]) == current_acc.hash {
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
	} else {
		return app.not_found()
	}
}

["/logout"]
pub fn (mut app App) handle_logout() vweb.Result { // handle login form
	if os.getenv("ENABLE_LOGIN") == "true" {
		app.set_cookie(http.Cookie{
			name: "account",
			value: "",
			path: "/",
		})
		return app.redirect("/login")
	} else {
		return app.not_found()
	}
}

["/assets/:path"]
pub fn (mut app App) assets(path string) vweb.Result { // serve assets files
	if os.getenv("ENABLE_LOGIN") == "true" {
		if accounts.index(app.get_cookie("account") or { return app.redirect("/login") }) >= 0 {
			return app.file("${os.getenv("ROOT")}/${os.getenv("ASSETS")}/$path")
		} else {
			return app.redirect("/login")
		}
	} else {
		return app.file("${os.getenv("ROOT")}/${os.getenv("ASSETS")}/$path")
	}
}

["/docs/:path"]
pub fn (mut app App) docs(path string) vweb.Result { // serve docs
	if os.getenv("ENABLE_LOGIN") == "true" {
		if accounts.index(app.get_cookie("account") or { return app.redirect("/login") }) >= 0 {
			return render(mut l, mut app, path)
		} else {
			return app.redirect("/login")
		}
	} else {
		return render(mut l, mut app, path)
	}
}