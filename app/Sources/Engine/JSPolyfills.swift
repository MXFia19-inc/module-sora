import Foundation

/// Polyfills JS injectés dans chaque contexte de module.
///
/// Fournit `fetchv2`/`fetch` (au-dessus du natif `__fetchNative`), `console`,
/// `setTimeout`/`clearTimeout`, ainsi que les classes manquantes de JavaScriptCore :
/// `URL` (utilisée par anime sama / nakios) et `Buffer` (wavewatch / movix / anime sama).
/// `atob`, `btoa`, `__fetchNative`, `__log` et `__setTimeout` sont fournis nativement.
enum JSPolyfills {
    static let source = #"""
    (function (g) {
      // ---- console -----------------------------------------------------------
      function fmt() {
        return Array.prototype.slice.call(arguments).map(function (a) {
          if (typeof a === 'string') return a;
          try { return JSON.stringify(a); } catch (e) { return String(a); }
        }).join(' ');
      }
      g.console = {
        log:   function () { __log('log',   fmt.apply(null, arguments)); },
        info:  function () { __log('info',  fmt.apply(null, arguments)); },
        warn:  function () { __log('warn',  fmt.apply(null, arguments)); },
        error: function () { __log('error', fmt.apply(null, arguments)); },
        debug: function () { __log('log',   fmt.apply(null, arguments)); }
      };

      // ---- timers ------------------------------------------------------------
      g.setTimeout  = function (cb, ms) { return __setTimeout(cb, ms || 0); };
      g.clearTimeout = function () {};
      g.setInterval  = function () { return 0; };
      g.clearInterval = function () {};

      // ---- fetchv2 / fetch ---------------------------------------------------
      g.fetchv2 = function (url, headers, method, body, redirect, encoding) {
        return __fetchNative(
          String(url),
          headers || {},
          method || 'GET',
          (body === undefined ? null : body),
          (redirect === undefined ? true : !!redirect),
          encoding || 'utf-8'
        ).then(function (r) {
          return {
            status: r.status,
            _status: r.status,
            ok: r.status >= 200 && r.status < 300,
            url: r.url,
            headers: r.headers,
            text: function () { return Promise.resolve(r._body); },
            json: function () { return Promise.resolve(JSON.parse(r._body)); }
          };
        });
      };
      g.fetch = function (url, options) {
        options = options || {};
        return g.fetchv2(url, options.headers, options.method, options.body, true, options.encoding);
      };

      // ---- URL ---------------------------------------------------------------
      if (typeof g.URL !== 'function') {
        function URLShim(url, base) {
          var u = String(url);
          if (base && !/^[a-zA-Z][a-zA-Z0-9+.\-]*:\/\//.test(u)) {
            var b = new URLShim(base);
            if (u.charAt(0) === '/') u = b.origin + u;
            else u = b.origin + b.pathname.replace(/[^/]*$/, '') + u;
          }
          var m = u.match(/^([a-zA-Z][a-zA-Z0-9+.\-]*:)\/\/([^/?#]*)([^?#]*)(\?[^#]*)?(#.*)?$/);
          if (!m) {
            this.href = u; this.protocol = ''; this.host = ''; this.hostname = '';
            this.port = ''; this.origin = ''; this.pathname = u; this.search = ''; this.hash = '';
            return;
          }
          this.protocol = m[1];
          this.host = m[2];
          var hp = m[2].split(':');
          this.hostname = hp[0];
          this.port = hp[1] || '';
          this.pathname = m[3] || '/';
          this.search = m[4] || '';
          this.hash = m[5] || '';
          this.origin = this.protocol + '//' + this.host;
          this.href = u;
        }
        URLShim.prototype.toString = function () { return this.href; };
        g.URL = URLShim;
      }

      // ---- Buffer (base64 <-> utf-8/binary) ----------------------------------
      if (typeof g.Buffer === 'undefined') {
        function decodeUTF8(bin) {
          try {
            var out = '', i = 0, len = bin.length;
            while (i < len) {
              var c = bin.charCodeAt(i++) & 0xff;
              if (c < 0x80) { out += String.fromCharCode(c); }
              else if (c < 0xE0) { out += String.fromCharCode(((c & 0x1F) << 6) | (bin.charCodeAt(i++) & 0x3F)); }
              else if (c < 0xF0) { out += String.fromCharCode(((c & 0x0F) << 12) | ((bin.charCodeAt(i++) & 0x3F) << 6) | (bin.charCodeAt(i++) & 0x3F)); }
              else {
                var cp = ((c & 0x07) << 18) | ((bin.charCodeAt(i++) & 0x3F) << 12) | ((bin.charCodeAt(i++) & 0x3F) << 6) | (bin.charCodeAt(i++) & 0x3F);
                cp -= 0x10000;
                out += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
              }
            }
            return out;
          } catch (e) { return bin; }
        }
        function encodeUTF8(str) {
          var out = '';
          for (var i = 0; i < str.length; i++) {
            var c = str.charCodeAt(i);
            if (c < 0x80) out += String.fromCharCode(c);
            else if (c < 0x800) out += String.fromCharCode(0xC0 | (c >> 6), 0x80 | (c & 0x3F));
            else out += String.fromCharCode(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F));
          }
          return out;
        }
        function BufferShim(data, enc) { this._data = String(data); this._enc = enc; }
        BufferShim.prototype.toString = function (target) {
          target = (target || 'utf-8').toLowerCase();
          if (this._enc === 'base64') {
            var bin = atob(this._data);
            return (target === 'binary' || target === 'latin1') ? bin : decodeUTF8(bin);
          }
          if (this._enc === 'utf-8' || this._enc === 'utf8') {
            return (target === 'base64') ? btoa(encodeUTF8(this._data)) : this._data;
          }
          if (target === 'base64') return btoa(this._data);
          return this._data;
        };
        g.Buffer = {
          from: function (data, enc) { return new BufferShim(data, (enc || 'utf-8').toLowerCase()); }
        };
      }
    })(this);
    """#
}
