(() => {
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __require = /* @__PURE__ */ ((x) => typeof require !== "undefined" ? require : typeof Proxy !== "undefined" ? new Proxy(x, {
    get: (a, b) => (typeof require !== "undefined" ? require : a)[b]
  }) : x)(function(x) {
    if (typeof require !== "undefined") return require.apply(this, arguments);
    throw Error('Dynamic require of "' + x + '" is not supported');
  });
  var __commonJS = (cb, mod) => function __require2() {
    try {
      return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
    } catch (e) {
      throw mod = 0, e;
    }
  };

  // node_modules/base64-js/index.js
  var require_base64_js = __commonJS({
    "node_modules/base64-js/index.js"(exports) {
      "use strict";
      exports.byteLength = byteLength;
      exports.toByteArray = toByteArray;
      exports.fromByteArray = fromByteArray;
      var lookup = [];
      var revLookup = [];
      var Arr = typeof Uint8Array !== "undefined" ? Uint8Array : Array;
      var code = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
      for (i = 0, len = code.length; i < len; ++i) {
        lookup[i] = code[i];
        revLookup[code.charCodeAt(i)] = i;
      }
      var i;
      var len;
      revLookup["-".charCodeAt(0)] = 62;
      revLookup["_".charCodeAt(0)] = 63;
      function getLens(b64) {
        var len2 = b64.length;
        if (len2 % 4 > 0) {
          throw new Error("Invalid string. Length must be a multiple of 4");
        }
        var validLen = b64.indexOf("=");
        if (validLen === -1) validLen = len2;
        var placeHoldersLen = validLen === len2 ? 0 : 4 - validLen % 4;
        return [validLen, placeHoldersLen];
      }
      function byteLength(b64) {
        var lens = getLens(b64);
        var validLen = lens[0];
        var placeHoldersLen = lens[1];
        return (validLen + placeHoldersLen) * 3 / 4 - placeHoldersLen;
      }
      function _byteLength(b64, validLen, placeHoldersLen) {
        return (validLen + placeHoldersLen) * 3 / 4 - placeHoldersLen;
      }
      function toByteArray(b64) {
        var tmp;
        var lens = getLens(b64);
        var validLen = lens[0];
        var placeHoldersLen = lens[1];
        var arr = new Arr(_byteLength(b64, validLen, placeHoldersLen));
        var curByte = 0;
        var len2 = placeHoldersLen > 0 ? validLen - 4 : validLen;
        var i2;
        for (i2 = 0; i2 < len2; i2 += 4) {
          tmp = revLookup[b64.charCodeAt(i2)] << 18 | revLookup[b64.charCodeAt(i2 + 1)] << 12 | revLookup[b64.charCodeAt(i2 + 2)] << 6 | revLookup[b64.charCodeAt(i2 + 3)];
          arr[curByte++] = tmp >> 16 & 255;
          arr[curByte++] = tmp >> 8 & 255;
          arr[curByte++] = tmp & 255;
        }
        if (placeHoldersLen === 2) {
          tmp = revLookup[b64.charCodeAt(i2)] << 2 | revLookup[b64.charCodeAt(i2 + 1)] >> 4;
          arr[curByte++] = tmp & 255;
        }
        if (placeHoldersLen === 1) {
          tmp = revLookup[b64.charCodeAt(i2)] << 10 | revLookup[b64.charCodeAt(i2 + 1)] << 4 | revLookup[b64.charCodeAt(i2 + 2)] >> 2;
          arr[curByte++] = tmp >> 8 & 255;
          arr[curByte++] = tmp & 255;
        }
        return arr;
      }
      function tripletToBase64(num) {
        return lookup[num >> 18 & 63] + lookup[num >> 12 & 63] + lookup[num >> 6 & 63] + lookup[num & 63];
      }
      function encodeChunk(uint8, start, end) {
        var tmp;
        var output = [];
        for (var i2 = start; i2 < end; i2 += 3) {
          tmp = (uint8[i2] << 16 & 16711680) + (uint8[i2 + 1] << 8 & 65280) + (uint8[i2 + 2] & 255);
          output.push(tripletToBase64(tmp));
        }
        return output.join("");
      }
      function fromByteArray(uint8) {
        var tmp;
        var len2 = uint8.length;
        var extraBytes = len2 % 3;
        var parts = [];
        var maxChunkLength = 16383;
        for (var i2 = 0, len22 = len2 - extraBytes; i2 < len22; i2 += maxChunkLength) {
          parts.push(encodeChunk(uint8, i2, i2 + maxChunkLength > len22 ? len22 : i2 + maxChunkLength));
        }
        if (extraBytes === 1) {
          tmp = uint8[len2 - 1];
          parts.push(
            lookup[tmp >> 2] + lookup[tmp << 4 & 63] + "=="
          );
        } else if (extraBytes === 2) {
          tmp = (uint8[len2 - 2] << 8) + uint8[len2 - 1];
          parts.push(
            lookup[tmp >> 10] + lookup[tmp >> 4 & 63] + lookup[tmp << 2 & 63] + "="
          );
        }
        return parts.join("");
      }
    }
  });

  // node_modules/ieee754/index.js
  var require_ieee754 = __commonJS({
    "node_modules/ieee754/index.js"(exports) {
      exports.read = function(buffer, offset, isLE, mLen, nBytes) {
        var e, m;
        var eLen = nBytes * 8 - mLen - 1;
        var eMax = (1 << eLen) - 1;
        var eBias = eMax >> 1;
        var nBits = -7;
        var i = isLE ? nBytes - 1 : 0;
        var d = isLE ? -1 : 1;
        var s = buffer[offset + i];
        i += d;
        e = s & (1 << -nBits) - 1;
        s >>= -nBits;
        nBits += eLen;
        for (; nBits > 0; e = e * 256 + buffer[offset + i], i += d, nBits -= 8) {
        }
        m = e & (1 << -nBits) - 1;
        e >>= -nBits;
        nBits += mLen;
        for (; nBits > 0; m = m * 256 + buffer[offset + i], i += d, nBits -= 8) {
        }
        if (e === 0) {
          e = 1 - eBias;
        } else if (e === eMax) {
          return m ? NaN : (s ? -1 : 1) * Infinity;
        } else {
          m = m + Math.pow(2, mLen);
          e = e - eBias;
        }
        return (s ? -1 : 1) * m * Math.pow(2, e - mLen);
      };
      exports.write = function(buffer, value, offset, isLE, mLen, nBytes) {
        var e, m, c;
        var eLen = nBytes * 8 - mLen - 1;
        var eMax = (1 << eLen) - 1;
        var eBias = eMax >> 1;
        var rt = mLen === 23 ? Math.pow(2, -24) - Math.pow(2, -77) : 0;
        var i = isLE ? 0 : nBytes - 1;
        var d = isLE ? 1 : -1;
        var s = value < 0 || value === 0 && 1 / value < 0 ? 1 : 0;
        value = Math.abs(value);
        if (isNaN(value) || value === Infinity) {
          m = isNaN(value) ? 1 : 0;
          e = eMax;
        } else {
          e = Math.floor(Math.log(value) / Math.LN2);
          if (value * (c = Math.pow(2, -e)) < 1) {
            e--;
            c *= 2;
          }
          if (e + eBias >= 1) {
            value += rt / c;
          } else {
            value += rt * Math.pow(2, 1 - eBias);
          }
          if (value * c >= 2) {
            e++;
            c /= 2;
          }
          if (e + eBias >= eMax) {
            m = 0;
            e = eMax;
          } else if (e + eBias >= 1) {
            m = (value * c - 1) * Math.pow(2, mLen);
            e = e + eBias;
          } else {
            m = value * Math.pow(2, eBias - 1) * Math.pow(2, mLen);
            e = 0;
          }
        }
        for (; mLen >= 8; buffer[offset + i] = m & 255, i += d, m /= 256, mLen -= 8) {
        }
        e = e << mLen | m;
        eLen += mLen;
        for (; eLen > 0; buffer[offset + i] = e & 255, i += d, e /= 256, eLen -= 8) {
        }
        buffer[offset + i - d] |= s * 128;
      };
    }
  });

  // node_modules/buffer/index.js
  var require_buffer = __commonJS({
    "node_modules/buffer/index.js"(exports) {
      "use strict";
      var base64 = require_base64_js();
      var ieee754 = require_ieee754();
      var customInspectSymbol = typeof Symbol === "function" && typeof Symbol["for"] === "function" ? Symbol["for"]("nodejs.util.inspect.custom") : null;
      exports.Buffer = Buffer2;
      exports.SlowBuffer = SlowBuffer;
      exports.INSPECT_MAX_BYTES = 50;
      var K_MAX_LENGTH = 2147483647;
      exports.kMaxLength = K_MAX_LENGTH;
      Buffer2.TYPED_ARRAY_SUPPORT = typedArraySupport();
      if (!Buffer2.TYPED_ARRAY_SUPPORT && typeof console !== "undefined" && typeof console.error === "function") {
        console.error(
          "This browser lacks typed array (Uint8Array) support which is required by `buffer` v5.x. Use `buffer` v4.x if you require old browser support."
        );
      }
      function typedArraySupport() {
        try {
          const arr = new Uint8Array(1);
          const proto = { foo: function() {
            return 42;
          } };
          Object.setPrototypeOf(proto, Uint8Array.prototype);
          Object.setPrototypeOf(arr, proto);
          return arr.foo() === 42;
        } catch (e) {
          return false;
        }
      }
      Object.defineProperty(Buffer2.prototype, "parent", {
        enumerable: true,
        get: function() {
          if (!Buffer2.isBuffer(this)) return void 0;
          return this.buffer;
        }
      });
      Object.defineProperty(Buffer2.prototype, "offset", {
        enumerable: true,
        get: function() {
          if (!Buffer2.isBuffer(this)) return void 0;
          return this.byteOffset;
        }
      });
      function createBuffer(length) {
        if (length > K_MAX_LENGTH) {
          throw new RangeError('The value "' + length + '" is invalid for option "size"');
        }
        const buf = new Uint8Array(length);
        Object.setPrototypeOf(buf, Buffer2.prototype);
        return buf;
      }
      function Buffer2(arg, encodingOrOffset, length) {
        if (typeof arg === "number") {
          if (typeof encodingOrOffset === "string") {
            throw new TypeError(
              'The "string" argument must be of type string. Received type number'
            );
          }
          return allocUnsafe(arg);
        }
        return from(arg, encodingOrOffset, length);
      }
      Buffer2.poolSize = 8192;
      function from(value, encodingOrOffset, length) {
        if (typeof value === "string") {
          return fromString(value, encodingOrOffset);
        }
        if (ArrayBuffer.isView(value)) {
          return fromArrayView(value);
        }
        if (value == null) {
          throw new TypeError(
            "The first argument must be one of type string, Buffer, ArrayBuffer, Array, or Array-like Object. Received type " + typeof value
          );
        }
        if (isInstance(value, ArrayBuffer) || value && isInstance(value.buffer, ArrayBuffer)) {
          return fromArrayBuffer(value, encodingOrOffset, length);
        }
        if (typeof SharedArrayBuffer !== "undefined" && (isInstance(value, SharedArrayBuffer) || value && isInstance(value.buffer, SharedArrayBuffer))) {
          return fromArrayBuffer(value, encodingOrOffset, length);
        }
        if (typeof value === "number") {
          throw new TypeError(
            'The "value" argument must not be of type number. Received type number'
          );
        }
        const valueOf = value.valueOf && value.valueOf();
        if (valueOf != null && valueOf !== value) {
          return Buffer2.from(valueOf, encodingOrOffset, length);
        }
        const b = fromObject(value);
        if (b) return b;
        if (typeof Symbol !== "undefined" && Symbol.toPrimitive != null && typeof value[Symbol.toPrimitive] === "function") {
          return Buffer2.from(value[Symbol.toPrimitive]("string"), encodingOrOffset, length);
        }
        throw new TypeError(
          "The first argument must be one of type string, Buffer, ArrayBuffer, Array, or Array-like Object. Received type " + typeof value
        );
      }
      Buffer2.from = function(value, encodingOrOffset, length) {
        return from(value, encodingOrOffset, length);
      };
      Object.setPrototypeOf(Buffer2.prototype, Uint8Array.prototype);
      Object.setPrototypeOf(Buffer2, Uint8Array);
      function assertSize(size) {
        if (typeof size !== "number") {
          throw new TypeError('"size" argument must be of type number');
        } else if (size < 0) {
          throw new RangeError('The value "' + size + '" is invalid for option "size"');
        }
      }
      function alloc(size, fill, encoding) {
        assertSize(size);
        if (size <= 0) {
          return createBuffer(size);
        }
        if (fill !== void 0) {
          return typeof encoding === "string" ? createBuffer(size).fill(fill, encoding) : createBuffer(size).fill(fill);
        }
        return createBuffer(size);
      }
      Buffer2.alloc = function(size, fill, encoding) {
        return alloc(size, fill, encoding);
      };
      function allocUnsafe(size) {
        assertSize(size);
        return createBuffer(size < 0 ? 0 : checked(size) | 0);
      }
      Buffer2.allocUnsafe = function(size) {
        return allocUnsafe(size);
      };
      Buffer2.allocUnsafeSlow = function(size) {
        return allocUnsafe(size);
      };
      function fromString(string, encoding) {
        if (typeof encoding !== "string" || encoding === "") {
          encoding = "utf8";
        }
        if (!Buffer2.isEncoding(encoding)) {
          throw new TypeError("Unknown encoding: " + encoding);
        }
        const length = byteLength(string, encoding) | 0;
        let buf = createBuffer(length);
        const actual = buf.write(string, encoding);
        if (actual !== length) {
          buf = buf.slice(0, actual);
        }
        return buf;
      }
      function fromArrayLike(array) {
        const length = array.length < 0 ? 0 : checked(array.length) | 0;
        const buf = createBuffer(length);
        for (let i = 0; i < length; i += 1) {
          buf[i] = array[i] & 255;
        }
        return buf;
      }
      function fromArrayView(arrayView) {
        if (isInstance(arrayView, Uint8Array)) {
          const copy = new Uint8Array(arrayView);
          return fromArrayBuffer(copy.buffer, copy.byteOffset, copy.byteLength);
        }
        return fromArrayLike(arrayView);
      }
      function fromArrayBuffer(array, byteOffset, length) {
        if (byteOffset < 0 || array.byteLength < byteOffset) {
          throw new RangeError('"offset" is outside of buffer bounds');
        }
        if (array.byteLength < byteOffset + (length || 0)) {
          throw new RangeError('"length" is outside of buffer bounds');
        }
        let buf;
        if (byteOffset === void 0 && length === void 0) {
          buf = new Uint8Array(array);
        } else if (length === void 0) {
          buf = new Uint8Array(array, byteOffset);
        } else {
          buf = new Uint8Array(array, byteOffset, length);
        }
        Object.setPrototypeOf(buf, Buffer2.prototype);
        return buf;
      }
      function fromObject(obj) {
        if (Buffer2.isBuffer(obj)) {
          const len = checked(obj.length) | 0;
          const buf = createBuffer(len);
          if (buf.length === 0) {
            return buf;
          }
          obj.copy(buf, 0, 0, len);
          return buf;
        }
        if (obj.length !== void 0) {
          if (typeof obj.length !== "number" || numberIsNaN(obj.length)) {
            return createBuffer(0);
          }
          return fromArrayLike(obj);
        }
        if (obj.type === "Buffer" && Array.isArray(obj.data)) {
          return fromArrayLike(obj.data);
        }
      }
      function checked(length) {
        if (length >= K_MAX_LENGTH) {
          throw new RangeError("Attempt to allocate Buffer larger than maximum size: 0x" + K_MAX_LENGTH.toString(16) + " bytes");
        }
        return length | 0;
      }
      function SlowBuffer(length) {
        if (+length != length) {
          length = 0;
        }
        return Buffer2.alloc(+length);
      }
      Buffer2.isBuffer = function isBuffer(b) {
        return b != null && b._isBuffer === true && b !== Buffer2.prototype;
      };
      Buffer2.compare = function compare(a, b) {
        if (isInstance(a, Uint8Array)) a = Buffer2.from(a, a.offset, a.byteLength);
        if (isInstance(b, Uint8Array)) b = Buffer2.from(b, b.offset, b.byteLength);
        if (!Buffer2.isBuffer(a) || !Buffer2.isBuffer(b)) {
          throw new TypeError(
            'The "buf1", "buf2" arguments must be one of type Buffer or Uint8Array'
          );
        }
        if (a === b) return 0;
        let x = a.length;
        let y = b.length;
        for (let i = 0, len = Math.min(x, y); i < len; ++i) {
          if (a[i] !== b[i]) {
            x = a[i];
            y = b[i];
            break;
          }
        }
        if (x < y) return -1;
        if (y < x) return 1;
        return 0;
      };
      Buffer2.isEncoding = function isEncoding(encoding) {
        switch (String(encoding).toLowerCase()) {
          case "hex":
          case "utf8":
          case "utf-8":
          case "ascii":
          case "latin1":
          case "binary":
          case "base64":
          case "ucs2":
          case "ucs-2":
          case "utf16le":
          case "utf-16le":
            return true;
          default:
            return false;
        }
      };
      Buffer2.concat = function concat(list, length) {
        if (!Array.isArray(list)) {
          throw new TypeError('"list" argument must be an Array of Buffers');
        }
        if (list.length === 0) {
          return Buffer2.alloc(0);
        }
        let i;
        if (length === void 0) {
          length = 0;
          for (i = 0; i < list.length; ++i) {
            length += list[i].length;
          }
        }
        const buffer = Buffer2.allocUnsafe(length);
        let pos = 0;
        for (i = 0; i < list.length; ++i) {
          let buf = list[i];
          if (isInstance(buf, Uint8Array)) {
            if (pos + buf.length > buffer.length) {
              if (!Buffer2.isBuffer(buf)) buf = Buffer2.from(buf);
              buf.copy(buffer, pos);
            } else {
              Uint8Array.prototype.set.call(
                buffer,
                buf,
                pos
              );
            }
          } else if (!Buffer2.isBuffer(buf)) {
            throw new TypeError('"list" argument must be an Array of Buffers');
          } else {
            buf.copy(buffer, pos);
          }
          pos += buf.length;
        }
        return buffer;
      };
      function byteLength(string, encoding) {
        if (Buffer2.isBuffer(string)) {
          return string.length;
        }
        if (ArrayBuffer.isView(string) || isInstance(string, ArrayBuffer)) {
          return string.byteLength;
        }
        if (typeof string !== "string") {
          throw new TypeError(
            'The "string" argument must be one of type string, Buffer, or ArrayBuffer. Received type ' + typeof string
          );
        }
        const len = string.length;
        const mustMatch = arguments.length > 2 && arguments[2] === true;
        if (!mustMatch && len === 0) return 0;
        let loweredCase = false;
        for (; ; ) {
          switch (encoding) {
            case "ascii":
            case "latin1":
            case "binary":
              return len;
            case "utf8":
            case "utf-8":
              return utf8ToBytes(string).length;
            case "ucs2":
            case "ucs-2":
            case "utf16le":
            case "utf-16le":
              return len * 2;
            case "hex":
              return len >>> 1;
            case "base64":
              return base64ToBytes(string).length;
            default:
              if (loweredCase) {
                return mustMatch ? -1 : utf8ToBytes(string).length;
              }
              encoding = ("" + encoding).toLowerCase();
              loweredCase = true;
          }
        }
      }
      Buffer2.byteLength = byteLength;
      function slowToString(encoding, start, end) {
        let loweredCase = false;
        if (start === void 0 || start < 0) {
          start = 0;
        }
        if (start > this.length) {
          return "";
        }
        if (end === void 0 || end > this.length) {
          end = this.length;
        }
        if (end <= 0) {
          return "";
        }
        end >>>= 0;
        start >>>= 0;
        if (end <= start) {
          return "";
        }
        if (!encoding) encoding = "utf8";
        while (true) {
          switch (encoding) {
            case "hex":
              return hexSlice(this, start, end);
            case "utf8":
            case "utf-8":
              return utf8Slice(this, start, end);
            case "ascii":
              return asciiSlice(this, start, end);
            case "latin1":
            case "binary":
              return latin1Slice(this, start, end);
            case "base64":
              return base64Slice(this, start, end);
            case "ucs2":
            case "ucs-2":
            case "utf16le":
            case "utf-16le":
              return utf16leSlice(this, start, end);
            default:
              if (loweredCase) throw new TypeError("Unknown encoding: " + encoding);
              encoding = (encoding + "").toLowerCase();
              loweredCase = true;
          }
        }
      }
      Buffer2.prototype._isBuffer = true;
      function swap(b, n, m) {
        const i = b[n];
        b[n] = b[m];
        b[m] = i;
      }
      Buffer2.prototype.swap16 = function swap16() {
        const len = this.length;
        if (len % 2 !== 0) {
          throw new RangeError("Buffer size must be a multiple of 16-bits");
        }
        for (let i = 0; i < len; i += 2) {
          swap(this, i, i + 1);
        }
        return this;
      };
      Buffer2.prototype.swap32 = function swap32() {
        const len = this.length;
        if (len % 4 !== 0) {
          throw new RangeError("Buffer size must be a multiple of 32-bits");
        }
        for (let i = 0; i < len; i += 4) {
          swap(this, i, i + 3);
          swap(this, i + 1, i + 2);
        }
        return this;
      };
      Buffer2.prototype.swap64 = function swap64() {
        const len = this.length;
        if (len % 8 !== 0) {
          throw new RangeError("Buffer size must be a multiple of 64-bits");
        }
        for (let i = 0; i < len; i += 8) {
          swap(this, i, i + 7);
          swap(this, i + 1, i + 6);
          swap(this, i + 2, i + 5);
          swap(this, i + 3, i + 4);
        }
        return this;
      };
      Buffer2.prototype.toString = function toString() {
        const length = this.length;
        if (length === 0) return "";
        if (arguments.length === 0) return utf8Slice(this, 0, length);
        return slowToString.apply(this, arguments);
      };
      Buffer2.prototype.toLocaleString = Buffer2.prototype.toString;
      Buffer2.prototype.equals = function equals(b) {
        if (!Buffer2.isBuffer(b)) throw new TypeError("Argument must be a Buffer");
        if (this === b) return true;
        return Buffer2.compare(this, b) === 0;
      };
      Buffer2.prototype.inspect = function inspect() {
        let str = "";
        const max = exports.INSPECT_MAX_BYTES;
        str = this.toString("hex", 0, max).replace(/(.{2})/g, "$1 ").trim();
        if (this.length > max) str += " ... ";
        return "<Buffer " + str + ">";
      };
      if (customInspectSymbol) {
        Buffer2.prototype[customInspectSymbol] = Buffer2.prototype.inspect;
      }
      Buffer2.prototype.compare = function compare(target, start, end, thisStart, thisEnd) {
        if (isInstance(target, Uint8Array)) {
          target = Buffer2.from(target, target.offset, target.byteLength);
        }
        if (!Buffer2.isBuffer(target)) {
          throw new TypeError(
            'The "target" argument must be one of type Buffer or Uint8Array. Received type ' + typeof target
          );
        }
        if (start === void 0) {
          start = 0;
        }
        if (end === void 0) {
          end = target ? target.length : 0;
        }
        if (thisStart === void 0) {
          thisStart = 0;
        }
        if (thisEnd === void 0) {
          thisEnd = this.length;
        }
        if (start < 0 || end > target.length || thisStart < 0 || thisEnd > this.length) {
          throw new RangeError("out of range index");
        }
        if (thisStart >= thisEnd && start >= end) {
          return 0;
        }
        if (thisStart >= thisEnd) {
          return -1;
        }
        if (start >= end) {
          return 1;
        }
        start >>>= 0;
        end >>>= 0;
        thisStart >>>= 0;
        thisEnd >>>= 0;
        if (this === target) return 0;
        let x = thisEnd - thisStart;
        let y = end - start;
        const len = Math.min(x, y);
        const thisCopy = this.slice(thisStart, thisEnd);
        const targetCopy = target.slice(start, end);
        for (let i = 0; i < len; ++i) {
          if (thisCopy[i] !== targetCopy[i]) {
            x = thisCopy[i];
            y = targetCopy[i];
            break;
          }
        }
        if (x < y) return -1;
        if (y < x) return 1;
        return 0;
      };
      function bidirectionalIndexOf(buffer, val, byteOffset, encoding, dir) {
        if (buffer.length === 0) return -1;
        if (typeof byteOffset === "string") {
          encoding = byteOffset;
          byteOffset = 0;
        } else if (byteOffset > 2147483647) {
          byteOffset = 2147483647;
        } else if (byteOffset < -2147483648) {
          byteOffset = -2147483648;
        }
        byteOffset = +byteOffset;
        if (numberIsNaN(byteOffset)) {
          byteOffset = dir ? 0 : buffer.length - 1;
        }
        if (byteOffset < 0) byteOffset = buffer.length + byteOffset;
        if (byteOffset >= buffer.length) {
          if (dir) return -1;
          else byteOffset = buffer.length - 1;
        } else if (byteOffset < 0) {
          if (dir) byteOffset = 0;
          else return -1;
        }
        if (typeof val === "string") {
          val = Buffer2.from(val, encoding);
        }
        if (Buffer2.isBuffer(val)) {
          if (val.length === 0) {
            return -1;
          }
          return arrayIndexOf(buffer, val, byteOffset, encoding, dir);
        } else if (typeof val === "number") {
          val = val & 255;
          if (typeof Uint8Array.prototype.indexOf === "function") {
            if (dir) {
              return Uint8Array.prototype.indexOf.call(buffer, val, byteOffset);
            } else {
              return Uint8Array.prototype.lastIndexOf.call(buffer, val, byteOffset);
            }
          }
          return arrayIndexOf(buffer, [val], byteOffset, encoding, dir);
        }
        throw new TypeError("val must be string, number or Buffer");
      }
      function arrayIndexOf(arr, val, byteOffset, encoding, dir) {
        let indexSize = 1;
        let arrLength = arr.length;
        let valLength = val.length;
        if (encoding !== void 0) {
          encoding = String(encoding).toLowerCase();
          if (encoding === "ucs2" || encoding === "ucs-2" || encoding === "utf16le" || encoding === "utf-16le") {
            if (arr.length < 2 || val.length < 2) {
              return -1;
            }
            indexSize = 2;
            arrLength /= 2;
            valLength /= 2;
            byteOffset /= 2;
          }
        }
        function read(buf, i2) {
          if (indexSize === 1) {
            return buf[i2];
          } else {
            return buf.readUInt16BE(i2 * indexSize);
          }
        }
        let i;
        if (dir) {
          let foundIndex = -1;
          for (i = byteOffset; i < arrLength; i++) {
            if (read(arr, i) === read(val, foundIndex === -1 ? 0 : i - foundIndex)) {
              if (foundIndex === -1) foundIndex = i;
              if (i - foundIndex + 1 === valLength) return foundIndex * indexSize;
            } else {
              if (foundIndex !== -1) i -= i - foundIndex;
              foundIndex = -1;
            }
          }
        } else {
          if (byteOffset + valLength > arrLength) byteOffset = arrLength - valLength;
          for (i = byteOffset; i >= 0; i--) {
            let found = true;
            for (let j = 0; j < valLength; j++) {
              if (read(arr, i + j) !== read(val, j)) {
                found = false;
                break;
              }
            }
            if (found) return i;
          }
        }
        return -1;
      }
      Buffer2.prototype.includes = function includes(val, byteOffset, encoding) {
        return this.indexOf(val, byteOffset, encoding) !== -1;
      };
      Buffer2.prototype.indexOf = function indexOf(val, byteOffset, encoding) {
        return bidirectionalIndexOf(this, val, byteOffset, encoding, true);
      };
      Buffer2.prototype.lastIndexOf = function lastIndexOf(val, byteOffset, encoding) {
        return bidirectionalIndexOf(this, val, byteOffset, encoding, false);
      };
      function hexWrite(buf, string, offset, length) {
        offset = Number(offset) || 0;
        const remaining = buf.length - offset;
        if (!length) {
          length = remaining;
        } else {
          length = Number(length);
          if (length > remaining) {
            length = remaining;
          }
        }
        const strLen = string.length;
        if (length > strLen / 2) {
          length = strLen / 2;
        }
        let i;
        for (i = 0; i < length; ++i) {
          const parsed = parseInt(string.substr(i * 2, 2), 16);
          if (numberIsNaN(parsed)) return i;
          buf[offset + i] = parsed;
        }
        return i;
      }
      function utf8Write(buf, string, offset, length) {
        return blitBuffer(utf8ToBytes(string, buf.length - offset), buf, offset, length);
      }
      function asciiWrite(buf, string, offset, length) {
        return blitBuffer(asciiToBytes(string), buf, offset, length);
      }
      function base64Write(buf, string, offset, length) {
        return blitBuffer(base64ToBytes(string), buf, offset, length);
      }
      function ucs2Write(buf, string, offset, length) {
        return blitBuffer(utf16leToBytes(string, buf.length - offset), buf, offset, length);
      }
      Buffer2.prototype.write = function write(string, offset, length, encoding) {
        if (offset === void 0) {
          encoding = "utf8";
          length = this.length;
          offset = 0;
        } else if (length === void 0 && typeof offset === "string") {
          encoding = offset;
          length = this.length;
          offset = 0;
        } else if (isFinite(offset)) {
          offset = offset >>> 0;
          if (isFinite(length)) {
            length = length >>> 0;
            if (encoding === void 0) encoding = "utf8";
          } else {
            encoding = length;
            length = void 0;
          }
        } else {
          throw new Error(
            "Buffer.write(string, encoding, offset[, length]) is no longer supported"
          );
        }
        const remaining = this.length - offset;
        if (length === void 0 || length > remaining) length = remaining;
        if (string.length > 0 && (length < 0 || offset < 0) || offset > this.length) {
          throw new RangeError("Attempt to write outside buffer bounds");
        }
        if (!encoding) encoding = "utf8";
        let loweredCase = false;
        for (; ; ) {
          switch (encoding) {
            case "hex":
              return hexWrite(this, string, offset, length);
            case "utf8":
            case "utf-8":
              return utf8Write(this, string, offset, length);
            case "ascii":
            case "latin1":
            case "binary":
              return asciiWrite(this, string, offset, length);
            case "base64":
              return base64Write(this, string, offset, length);
            case "ucs2":
            case "ucs-2":
            case "utf16le":
            case "utf-16le":
              return ucs2Write(this, string, offset, length);
            default:
              if (loweredCase) throw new TypeError("Unknown encoding: " + encoding);
              encoding = ("" + encoding).toLowerCase();
              loweredCase = true;
          }
        }
      };
      Buffer2.prototype.toJSON = function toJSON() {
        return {
          type: "Buffer",
          data: Array.prototype.slice.call(this._arr || this, 0)
        };
      };
      function base64Slice(buf, start, end) {
        if (start === 0 && end === buf.length) {
          return base64.fromByteArray(buf);
        } else {
          return base64.fromByteArray(buf.slice(start, end));
        }
      }
      function utf8Slice(buf, start, end) {
        end = Math.min(buf.length, end);
        const res = [];
        let i = start;
        while (i < end) {
          const firstByte = buf[i];
          let codePoint = null;
          let bytesPerSequence = firstByte > 239 ? 4 : firstByte > 223 ? 3 : firstByte > 191 ? 2 : 1;
          if (i + bytesPerSequence <= end) {
            let secondByte, thirdByte, fourthByte, tempCodePoint;
            switch (bytesPerSequence) {
              case 1:
                if (firstByte < 128) {
                  codePoint = firstByte;
                }
                break;
              case 2:
                secondByte = buf[i + 1];
                if ((secondByte & 192) === 128) {
                  tempCodePoint = (firstByte & 31) << 6 | secondByte & 63;
                  if (tempCodePoint > 127) {
                    codePoint = tempCodePoint;
                  }
                }
                break;
              case 3:
                secondByte = buf[i + 1];
                thirdByte = buf[i + 2];
                if ((secondByte & 192) === 128 && (thirdByte & 192) === 128) {
                  tempCodePoint = (firstByte & 15) << 12 | (secondByte & 63) << 6 | thirdByte & 63;
                  if (tempCodePoint > 2047 && (tempCodePoint < 55296 || tempCodePoint > 57343)) {
                    codePoint = tempCodePoint;
                  }
                }
                break;
              case 4:
                secondByte = buf[i + 1];
                thirdByte = buf[i + 2];
                fourthByte = buf[i + 3];
                if ((secondByte & 192) === 128 && (thirdByte & 192) === 128 && (fourthByte & 192) === 128) {
                  tempCodePoint = (firstByte & 15) << 18 | (secondByte & 63) << 12 | (thirdByte & 63) << 6 | fourthByte & 63;
                  if (tempCodePoint > 65535 && tempCodePoint < 1114112) {
                    codePoint = tempCodePoint;
                  }
                }
            }
          }
          if (codePoint === null) {
            codePoint = 65533;
            bytesPerSequence = 1;
          } else if (codePoint > 65535) {
            codePoint -= 65536;
            res.push(codePoint >>> 10 & 1023 | 55296);
            codePoint = 56320 | codePoint & 1023;
          }
          res.push(codePoint);
          i += bytesPerSequence;
        }
        return decodeCodePointsArray(res);
      }
      var MAX_ARGUMENTS_LENGTH = 4096;
      function decodeCodePointsArray(codePoints) {
        const len = codePoints.length;
        if (len <= MAX_ARGUMENTS_LENGTH) {
          return String.fromCharCode.apply(String, codePoints);
        }
        let res = "";
        let i = 0;
        while (i < len) {
          res += String.fromCharCode.apply(
            String,
            codePoints.slice(i, i += MAX_ARGUMENTS_LENGTH)
          );
        }
        return res;
      }
      function asciiSlice(buf, start, end) {
        let ret = "";
        end = Math.min(buf.length, end);
        for (let i = start; i < end; ++i) {
          ret += String.fromCharCode(buf[i] & 127);
        }
        return ret;
      }
      function latin1Slice(buf, start, end) {
        let ret = "";
        end = Math.min(buf.length, end);
        for (let i = start; i < end; ++i) {
          ret += String.fromCharCode(buf[i]);
        }
        return ret;
      }
      function hexSlice(buf, start, end) {
        const len = buf.length;
        if (!start || start < 0) start = 0;
        if (!end || end < 0 || end > len) end = len;
        let out = "";
        for (let i = start; i < end; ++i) {
          out += hexSliceLookupTable[buf[i]];
        }
        return out;
      }
      function utf16leSlice(buf, start, end) {
        const bytes = buf.slice(start, end);
        let res = "";
        for (let i = 0; i < bytes.length - 1; i += 2) {
          res += String.fromCharCode(bytes[i] + bytes[i + 1] * 256);
        }
        return res;
      }
      Buffer2.prototype.slice = function slice(start, end) {
        const len = this.length;
        start = ~~start;
        end = end === void 0 ? len : ~~end;
        if (start < 0) {
          start += len;
          if (start < 0) start = 0;
        } else if (start > len) {
          start = len;
        }
        if (end < 0) {
          end += len;
          if (end < 0) end = 0;
        } else if (end > len) {
          end = len;
        }
        if (end < start) end = start;
        const newBuf = this.subarray(start, end);
        Object.setPrototypeOf(newBuf, Buffer2.prototype);
        return newBuf;
      };
      function checkOffset(offset, ext, length) {
        if (offset % 1 !== 0 || offset < 0) throw new RangeError("offset is not uint");
        if (offset + ext > length) throw new RangeError("Trying to access beyond buffer length");
      }
      Buffer2.prototype.readUintLE = Buffer2.prototype.readUIntLE = function readUIntLE(offset, byteLength2, noAssert) {
        offset = offset >>> 0;
        byteLength2 = byteLength2 >>> 0;
        if (!noAssert) checkOffset(offset, byteLength2, this.length);
        let val = this[offset];
        let mul = 1;
        let i = 0;
        while (++i < byteLength2 && (mul *= 256)) {
          val += this[offset + i] * mul;
        }
        return val;
      };
      Buffer2.prototype.readUintBE = Buffer2.prototype.readUIntBE = function readUIntBE(offset, byteLength2, noAssert) {
        offset = offset >>> 0;
        byteLength2 = byteLength2 >>> 0;
        if (!noAssert) {
          checkOffset(offset, byteLength2, this.length);
        }
        let val = this[offset + --byteLength2];
        let mul = 1;
        while (byteLength2 > 0 && (mul *= 256)) {
          val += this[offset + --byteLength2] * mul;
        }
        return val;
      };
      Buffer2.prototype.readUint8 = Buffer2.prototype.readUInt8 = function readUInt8(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 1, this.length);
        return this[offset];
      };
      Buffer2.prototype.readUint16LE = Buffer2.prototype.readUInt16LE = function readUInt16LE(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 2, this.length);
        return this[offset] | this[offset + 1] << 8;
      };
      Buffer2.prototype.readUint16BE = Buffer2.prototype.readUInt16BE = function readUInt16BE(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 2, this.length);
        return this[offset] << 8 | this[offset + 1];
      };
      Buffer2.prototype.readUint32LE = Buffer2.prototype.readUInt32LE = function readUInt32LE(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 4, this.length);
        return (this[offset] | this[offset + 1] << 8 | this[offset + 2] << 16) + this[offset + 3] * 16777216;
      };
      Buffer2.prototype.readUint32BE = Buffer2.prototype.readUInt32BE = function readUInt32BE(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 4, this.length);
        return this[offset] * 16777216 + (this[offset + 1] << 16 | this[offset + 2] << 8 | this[offset + 3]);
      };
      Buffer2.prototype.readBigUInt64LE = defineBigIntMethod(function readBigUInt64LE(offset) {
        offset = offset >>> 0;
        validateNumber(offset, "offset");
        const first = this[offset];
        const last = this[offset + 7];
        if (first === void 0 || last === void 0) {
          boundsError(offset, this.length - 8);
        }
        const lo = first + this[++offset] * 2 ** 8 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 24;
        const hi = this[++offset] + this[++offset] * 2 ** 8 + this[++offset] * 2 ** 16 + last * 2 ** 24;
        return BigInt(lo) + (BigInt(hi) << BigInt(32));
      });
      Buffer2.prototype.readBigUInt64BE = defineBigIntMethod(function readBigUInt64BE(offset) {
        offset = offset >>> 0;
        validateNumber(offset, "offset");
        const first = this[offset];
        const last = this[offset + 7];
        if (first === void 0 || last === void 0) {
          boundsError(offset, this.length - 8);
        }
        const hi = first * 2 ** 24 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 8 + this[++offset];
        const lo = this[++offset] * 2 ** 24 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 8 + last;
        return (BigInt(hi) << BigInt(32)) + BigInt(lo);
      });
      Buffer2.prototype.readIntLE = function readIntLE(offset, byteLength2, noAssert) {
        offset = offset >>> 0;
        byteLength2 = byteLength2 >>> 0;
        if (!noAssert) checkOffset(offset, byteLength2, this.length);
        let val = this[offset];
        let mul = 1;
        let i = 0;
        while (++i < byteLength2 && (mul *= 256)) {
          val += this[offset + i] * mul;
        }
        mul *= 128;
        if (val >= mul) val -= Math.pow(2, 8 * byteLength2);
        return val;
      };
      Buffer2.prototype.readIntBE = function readIntBE(offset, byteLength2, noAssert) {
        offset = offset >>> 0;
        byteLength2 = byteLength2 >>> 0;
        if (!noAssert) checkOffset(offset, byteLength2, this.length);
        let i = byteLength2;
        let mul = 1;
        let val = this[offset + --i];
        while (i > 0 && (mul *= 256)) {
          val += this[offset + --i] * mul;
        }
        mul *= 128;
        if (val >= mul) val -= Math.pow(2, 8 * byteLength2);
        return val;
      };
      Buffer2.prototype.readInt8 = function readInt8(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 1, this.length);
        if (!(this[offset] & 128)) return this[offset];
        return (255 - this[offset] + 1) * -1;
      };
      Buffer2.prototype.readInt16LE = function readInt16LE(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 2, this.length);
        const val = this[offset] | this[offset + 1] << 8;
        return val & 32768 ? val | 4294901760 : val;
      };
      Buffer2.prototype.readInt16BE = function readInt16BE(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 2, this.length);
        const val = this[offset + 1] | this[offset] << 8;
        return val & 32768 ? val | 4294901760 : val;
      };
      Buffer2.prototype.readInt32LE = function readInt32LE(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 4, this.length);
        return this[offset] | this[offset + 1] << 8 | this[offset + 2] << 16 | this[offset + 3] << 24;
      };
      Buffer2.prototype.readInt32BE = function readInt32BE(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 4, this.length);
        return this[offset] << 24 | this[offset + 1] << 16 | this[offset + 2] << 8 | this[offset + 3];
      };
      Buffer2.prototype.readBigInt64LE = defineBigIntMethod(function readBigInt64LE(offset) {
        offset = offset >>> 0;
        validateNumber(offset, "offset");
        const first = this[offset];
        const last = this[offset + 7];
        if (first === void 0 || last === void 0) {
          boundsError(offset, this.length - 8);
        }
        const val = this[offset + 4] + this[offset + 5] * 2 ** 8 + this[offset + 6] * 2 ** 16 + (last << 24);
        return (BigInt(val) << BigInt(32)) + BigInt(first + this[++offset] * 2 ** 8 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 24);
      });
      Buffer2.prototype.readBigInt64BE = defineBigIntMethod(function readBigInt64BE(offset) {
        offset = offset >>> 0;
        validateNumber(offset, "offset");
        const first = this[offset];
        const last = this[offset + 7];
        if (first === void 0 || last === void 0) {
          boundsError(offset, this.length - 8);
        }
        const val = (first << 24) + // Overflow
        this[++offset] * 2 ** 16 + this[++offset] * 2 ** 8 + this[++offset];
        return (BigInt(val) << BigInt(32)) + BigInt(this[++offset] * 2 ** 24 + this[++offset] * 2 ** 16 + this[++offset] * 2 ** 8 + last);
      });
      Buffer2.prototype.readFloatLE = function readFloatLE(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 4, this.length);
        return ieee754.read(this, offset, true, 23, 4);
      };
      Buffer2.prototype.readFloatBE = function readFloatBE(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 4, this.length);
        return ieee754.read(this, offset, false, 23, 4);
      };
      Buffer2.prototype.readDoubleLE = function readDoubleLE(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 8, this.length);
        return ieee754.read(this, offset, true, 52, 8);
      };
      Buffer2.prototype.readDoubleBE = function readDoubleBE(offset, noAssert) {
        offset = offset >>> 0;
        if (!noAssert) checkOffset(offset, 8, this.length);
        return ieee754.read(this, offset, false, 52, 8);
      };
      function checkInt(buf, value, offset, ext, max, min) {
        if (!Buffer2.isBuffer(buf)) throw new TypeError('"buffer" argument must be a Buffer instance');
        if (value > max || value < min) throw new RangeError('"value" argument is out of bounds');
        if (offset + ext > buf.length) throw new RangeError("Index out of range");
      }
      Buffer2.prototype.writeUintLE = Buffer2.prototype.writeUIntLE = function writeUIntLE(value, offset, byteLength2, noAssert) {
        value = +value;
        offset = offset >>> 0;
        byteLength2 = byteLength2 >>> 0;
        if (!noAssert) {
          const maxBytes = Math.pow(2, 8 * byteLength2) - 1;
          checkInt(this, value, offset, byteLength2, maxBytes, 0);
        }
        let mul = 1;
        let i = 0;
        this[offset] = value & 255;
        while (++i < byteLength2 && (mul *= 256)) {
          this[offset + i] = value / mul & 255;
        }
        return offset + byteLength2;
      };
      Buffer2.prototype.writeUintBE = Buffer2.prototype.writeUIntBE = function writeUIntBE(value, offset, byteLength2, noAssert) {
        value = +value;
        offset = offset >>> 0;
        byteLength2 = byteLength2 >>> 0;
        if (!noAssert) {
          const maxBytes = Math.pow(2, 8 * byteLength2) - 1;
          checkInt(this, value, offset, byteLength2, maxBytes, 0);
        }
        let i = byteLength2 - 1;
        let mul = 1;
        this[offset + i] = value & 255;
        while (--i >= 0 && (mul *= 256)) {
          this[offset + i] = value / mul & 255;
        }
        return offset + byteLength2;
      };
      Buffer2.prototype.writeUint8 = Buffer2.prototype.writeUInt8 = function writeUInt8(value, offset, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) checkInt(this, value, offset, 1, 255, 0);
        this[offset] = value & 255;
        return offset + 1;
      };
      Buffer2.prototype.writeUint16LE = Buffer2.prototype.writeUInt16LE = function writeUInt16LE(value, offset, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) checkInt(this, value, offset, 2, 65535, 0);
        this[offset] = value & 255;
        this[offset + 1] = value >>> 8;
        return offset + 2;
      };
      Buffer2.prototype.writeUint16BE = Buffer2.prototype.writeUInt16BE = function writeUInt16BE(value, offset, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) checkInt(this, value, offset, 2, 65535, 0);
        this[offset] = value >>> 8;
        this[offset + 1] = value & 255;
        return offset + 2;
      };
      Buffer2.prototype.writeUint32LE = Buffer2.prototype.writeUInt32LE = function writeUInt32LE(value, offset, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) checkInt(this, value, offset, 4, 4294967295, 0);
        this[offset + 3] = value >>> 24;
        this[offset + 2] = value >>> 16;
        this[offset + 1] = value >>> 8;
        this[offset] = value & 255;
        return offset + 4;
      };
      Buffer2.prototype.writeUint32BE = Buffer2.prototype.writeUInt32BE = function writeUInt32BE(value, offset, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) checkInt(this, value, offset, 4, 4294967295, 0);
        this[offset] = value >>> 24;
        this[offset + 1] = value >>> 16;
        this[offset + 2] = value >>> 8;
        this[offset + 3] = value & 255;
        return offset + 4;
      };
      function wrtBigUInt64LE(buf, value, offset, min, max) {
        checkIntBI(value, min, max, buf, offset, 7);
        let lo = Number(value & BigInt(4294967295));
        buf[offset++] = lo;
        lo = lo >> 8;
        buf[offset++] = lo;
        lo = lo >> 8;
        buf[offset++] = lo;
        lo = lo >> 8;
        buf[offset++] = lo;
        let hi = Number(value >> BigInt(32) & BigInt(4294967295));
        buf[offset++] = hi;
        hi = hi >> 8;
        buf[offset++] = hi;
        hi = hi >> 8;
        buf[offset++] = hi;
        hi = hi >> 8;
        buf[offset++] = hi;
        return offset;
      }
      function wrtBigUInt64BE(buf, value, offset, min, max) {
        checkIntBI(value, min, max, buf, offset, 7);
        let lo = Number(value & BigInt(4294967295));
        buf[offset + 7] = lo;
        lo = lo >> 8;
        buf[offset + 6] = lo;
        lo = lo >> 8;
        buf[offset + 5] = lo;
        lo = lo >> 8;
        buf[offset + 4] = lo;
        let hi = Number(value >> BigInt(32) & BigInt(4294967295));
        buf[offset + 3] = hi;
        hi = hi >> 8;
        buf[offset + 2] = hi;
        hi = hi >> 8;
        buf[offset + 1] = hi;
        hi = hi >> 8;
        buf[offset] = hi;
        return offset + 8;
      }
      Buffer2.prototype.writeBigUInt64LE = defineBigIntMethod(function writeBigUInt64LE(value, offset = 0) {
        return wrtBigUInt64LE(this, value, offset, BigInt(0), BigInt("0xffffffffffffffff"));
      });
      Buffer2.prototype.writeBigUInt64BE = defineBigIntMethod(function writeBigUInt64BE(value, offset = 0) {
        return wrtBigUInt64BE(this, value, offset, BigInt(0), BigInt("0xffffffffffffffff"));
      });
      Buffer2.prototype.writeIntLE = function writeIntLE(value, offset, byteLength2, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) {
          const limit = Math.pow(2, 8 * byteLength2 - 1);
          checkInt(this, value, offset, byteLength2, limit - 1, -limit);
        }
        let i = 0;
        let mul = 1;
        let sub = 0;
        this[offset] = value & 255;
        while (++i < byteLength2 && (mul *= 256)) {
          if (value < 0 && sub === 0 && this[offset + i - 1] !== 0) {
            sub = 1;
          }
          this[offset + i] = (value / mul >> 0) - sub & 255;
        }
        return offset + byteLength2;
      };
      Buffer2.prototype.writeIntBE = function writeIntBE(value, offset, byteLength2, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) {
          const limit = Math.pow(2, 8 * byteLength2 - 1);
          checkInt(this, value, offset, byteLength2, limit - 1, -limit);
        }
        let i = byteLength2 - 1;
        let mul = 1;
        let sub = 0;
        this[offset + i] = value & 255;
        while (--i >= 0 && (mul *= 256)) {
          if (value < 0 && sub === 0 && this[offset + i + 1] !== 0) {
            sub = 1;
          }
          this[offset + i] = (value / mul >> 0) - sub & 255;
        }
        return offset + byteLength2;
      };
      Buffer2.prototype.writeInt8 = function writeInt8(value, offset, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) checkInt(this, value, offset, 1, 127, -128);
        if (value < 0) value = 255 + value + 1;
        this[offset] = value & 255;
        return offset + 1;
      };
      Buffer2.prototype.writeInt16LE = function writeInt16LE(value, offset, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) checkInt(this, value, offset, 2, 32767, -32768);
        this[offset] = value & 255;
        this[offset + 1] = value >>> 8;
        return offset + 2;
      };
      Buffer2.prototype.writeInt16BE = function writeInt16BE(value, offset, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) checkInt(this, value, offset, 2, 32767, -32768);
        this[offset] = value >>> 8;
        this[offset + 1] = value & 255;
        return offset + 2;
      };
      Buffer2.prototype.writeInt32LE = function writeInt32LE(value, offset, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) checkInt(this, value, offset, 4, 2147483647, -2147483648);
        this[offset] = value & 255;
        this[offset + 1] = value >>> 8;
        this[offset + 2] = value >>> 16;
        this[offset + 3] = value >>> 24;
        return offset + 4;
      };
      Buffer2.prototype.writeInt32BE = function writeInt32BE(value, offset, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) checkInt(this, value, offset, 4, 2147483647, -2147483648);
        if (value < 0) value = 4294967295 + value + 1;
        this[offset] = value >>> 24;
        this[offset + 1] = value >>> 16;
        this[offset + 2] = value >>> 8;
        this[offset + 3] = value & 255;
        return offset + 4;
      };
      Buffer2.prototype.writeBigInt64LE = defineBigIntMethod(function writeBigInt64LE(value, offset = 0) {
        return wrtBigUInt64LE(this, value, offset, -BigInt("0x8000000000000000"), BigInt("0x7fffffffffffffff"));
      });
      Buffer2.prototype.writeBigInt64BE = defineBigIntMethod(function writeBigInt64BE(value, offset = 0) {
        return wrtBigUInt64BE(this, value, offset, -BigInt("0x8000000000000000"), BigInt("0x7fffffffffffffff"));
      });
      function checkIEEE754(buf, value, offset, ext, max, min) {
        if (offset + ext > buf.length) throw new RangeError("Index out of range");
        if (offset < 0) throw new RangeError("Index out of range");
      }
      function writeFloat(buf, value, offset, littleEndian, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) {
          checkIEEE754(buf, value, offset, 4, 34028234663852886e22, -34028234663852886e22);
        }
        ieee754.write(buf, value, offset, littleEndian, 23, 4);
        return offset + 4;
      }
      Buffer2.prototype.writeFloatLE = function writeFloatLE(value, offset, noAssert) {
        return writeFloat(this, value, offset, true, noAssert);
      };
      Buffer2.prototype.writeFloatBE = function writeFloatBE(value, offset, noAssert) {
        return writeFloat(this, value, offset, false, noAssert);
      };
      function writeDouble(buf, value, offset, littleEndian, noAssert) {
        value = +value;
        offset = offset >>> 0;
        if (!noAssert) {
          checkIEEE754(buf, value, offset, 8, 17976931348623157e292, -17976931348623157e292);
        }
        ieee754.write(buf, value, offset, littleEndian, 52, 8);
        return offset + 8;
      }
      Buffer2.prototype.writeDoubleLE = function writeDoubleLE(value, offset, noAssert) {
        return writeDouble(this, value, offset, true, noAssert);
      };
      Buffer2.prototype.writeDoubleBE = function writeDoubleBE(value, offset, noAssert) {
        return writeDouble(this, value, offset, false, noAssert);
      };
      Buffer2.prototype.copy = function copy(target, targetStart, start, end) {
        if (!Buffer2.isBuffer(target)) throw new TypeError("argument should be a Buffer");
        if (!start) start = 0;
        if (!end && end !== 0) end = this.length;
        if (targetStart >= target.length) targetStart = target.length;
        if (!targetStart) targetStart = 0;
        if (end > 0 && end < start) end = start;
        if (end === start) return 0;
        if (target.length === 0 || this.length === 0) return 0;
        if (targetStart < 0) {
          throw new RangeError("targetStart out of bounds");
        }
        if (start < 0 || start >= this.length) throw new RangeError("Index out of range");
        if (end < 0) throw new RangeError("sourceEnd out of bounds");
        if (end > this.length) end = this.length;
        if (target.length - targetStart < end - start) {
          end = target.length - targetStart + start;
        }
        const len = end - start;
        if (this === target && typeof Uint8Array.prototype.copyWithin === "function") {
          this.copyWithin(targetStart, start, end);
        } else {
          Uint8Array.prototype.set.call(
            target,
            this.subarray(start, end),
            targetStart
          );
        }
        return len;
      };
      Buffer2.prototype.fill = function fill(val, start, end, encoding) {
        if (typeof val === "string") {
          if (typeof start === "string") {
            encoding = start;
            start = 0;
            end = this.length;
          } else if (typeof end === "string") {
            encoding = end;
            end = this.length;
          }
          if (encoding !== void 0 && typeof encoding !== "string") {
            throw new TypeError("encoding must be a string");
          }
          if (typeof encoding === "string" && !Buffer2.isEncoding(encoding)) {
            throw new TypeError("Unknown encoding: " + encoding);
          }
          if (val.length === 1) {
            const code = val.charCodeAt(0);
            if (encoding === "utf8" && code < 128 || encoding === "latin1") {
              val = code;
            }
          }
        } else if (typeof val === "number") {
          val = val & 255;
        } else if (typeof val === "boolean") {
          val = Number(val);
        }
        if (start < 0 || this.length < start || this.length < end) {
          throw new RangeError("Out of range index");
        }
        if (end <= start) {
          return this;
        }
        start = start >>> 0;
        end = end === void 0 ? this.length : end >>> 0;
        if (!val) val = 0;
        let i;
        if (typeof val === "number") {
          for (i = start; i < end; ++i) {
            this[i] = val;
          }
        } else {
          const bytes = Buffer2.isBuffer(val) ? val : Buffer2.from(val, encoding);
          const len = bytes.length;
          if (len === 0) {
            throw new TypeError('The value "' + val + '" is invalid for argument "value"');
          }
          for (i = 0; i < end - start; ++i) {
            this[i + start] = bytes[i % len];
          }
        }
        return this;
      };
      var errors = {};
      function E(sym, getMessage, Base) {
        errors[sym] = class NodeError extends Base {
          constructor() {
            super();
            Object.defineProperty(this, "message", {
              value: getMessage.apply(this, arguments),
              writable: true,
              configurable: true
            });
            this.name = `${this.name} [${sym}]`;
            this.stack;
            delete this.name;
          }
          get code() {
            return sym;
          }
          set code(value) {
            Object.defineProperty(this, "code", {
              configurable: true,
              enumerable: true,
              value,
              writable: true
            });
          }
          toString() {
            return `${this.name} [${sym}]: ${this.message}`;
          }
        };
      }
      E(
        "ERR_BUFFER_OUT_OF_BOUNDS",
        function(name) {
          if (name) {
            return `${name} is outside of buffer bounds`;
          }
          return "Attempt to access memory outside buffer bounds";
        },
        RangeError
      );
      E(
        "ERR_INVALID_ARG_TYPE",
        function(name, actual) {
          return `The "${name}" argument must be of type number. Received type ${typeof actual}`;
        },
        TypeError
      );
      E(
        "ERR_OUT_OF_RANGE",
        function(str, range, input) {
          let msg = `The value of "${str}" is out of range.`;
          let received = input;
          if (Number.isInteger(input) && Math.abs(input) > 2 ** 32) {
            received = addNumericalSeparator(String(input));
          } else if (typeof input === "bigint") {
            received = String(input);
            if (input > BigInt(2) ** BigInt(32) || input < -(BigInt(2) ** BigInt(32))) {
              received = addNumericalSeparator(received);
            }
            received += "n";
          }
          msg += ` It must be ${range}. Received ${received}`;
          return msg;
        },
        RangeError
      );
      function addNumericalSeparator(val) {
        let res = "";
        let i = val.length;
        const start = val[0] === "-" ? 1 : 0;
        for (; i >= start + 4; i -= 3) {
          res = `_${val.slice(i - 3, i)}${res}`;
        }
        return `${val.slice(0, i)}${res}`;
      }
      function checkBounds(buf, offset, byteLength2) {
        validateNumber(offset, "offset");
        if (buf[offset] === void 0 || buf[offset + byteLength2] === void 0) {
          boundsError(offset, buf.length - (byteLength2 + 1));
        }
      }
      function checkIntBI(value, min, max, buf, offset, byteLength2) {
        if (value > max || value < min) {
          const n = typeof min === "bigint" ? "n" : "";
          let range;
          if (byteLength2 > 3) {
            if (min === 0 || min === BigInt(0)) {
              range = `>= 0${n} and < 2${n} ** ${(byteLength2 + 1) * 8}${n}`;
            } else {
              range = `>= -(2${n} ** ${(byteLength2 + 1) * 8 - 1}${n}) and < 2 ** ${(byteLength2 + 1) * 8 - 1}${n}`;
            }
          } else {
            range = `>= ${min}${n} and <= ${max}${n}`;
          }
          throw new errors.ERR_OUT_OF_RANGE("value", range, value);
        }
        checkBounds(buf, offset, byteLength2);
      }
      function validateNumber(value, name) {
        if (typeof value !== "number") {
          throw new errors.ERR_INVALID_ARG_TYPE(name, "number", value);
        }
      }
      function boundsError(value, length, type) {
        if (Math.floor(value) !== value) {
          validateNumber(value, type);
          throw new errors.ERR_OUT_OF_RANGE(type || "offset", "an integer", value);
        }
        if (length < 0) {
          throw new errors.ERR_BUFFER_OUT_OF_BOUNDS();
        }
        throw new errors.ERR_OUT_OF_RANGE(
          type || "offset",
          `>= ${type ? 1 : 0} and <= ${length}`,
          value
        );
      }
      var INVALID_BASE64_RE = /[^+/0-9A-Za-z-_]/g;
      function base64clean(str) {
        str = str.split("=")[0];
        str = str.trim().replace(INVALID_BASE64_RE, "");
        if (str.length < 2) return "";
        while (str.length % 4 !== 0) {
          str = str + "=";
        }
        return str;
      }
      function utf8ToBytes(string, units) {
        units = units || Infinity;
        let codePoint;
        const length = string.length;
        let leadSurrogate = null;
        const bytes = [];
        for (let i = 0; i < length; ++i) {
          codePoint = string.charCodeAt(i);
          if (codePoint > 55295 && codePoint < 57344) {
            if (!leadSurrogate) {
              if (codePoint > 56319) {
                if ((units -= 3) > -1) bytes.push(239, 191, 189);
                continue;
              } else if (i + 1 === length) {
                if ((units -= 3) > -1) bytes.push(239, 191, 189);
                continue;
              }
              leadSurrogate = codePoint;
              continue;
            }
            if (codePoint < 56320) {
              if ((units -= 3) > -1) bytes.push(239, 191, 189);
              leadSurrogate = codePoint;
              continue;
            }
            codePoint = (leadSurrogate - 55296 << 10 | codePoint - 56320) + 65536;
          } else if (leadSurrogate) {
            if ((units -= 3) > -1) bytes.push(239, 191, 189);
          }
          leadSurrogate = null;
          if (codePoint < 128) {
            if ((units -= 1) < 0) break;
            bytes.push(codePoint);
          } else if (codePoint < 2048) {
            if ((units -= 2) < 0) break;
            bytes.push(
              codePoint >> 6 | 192,
              codePoint & 63 | 128
            );
          } else if (codePoint < 65536) {
            if ((units -= 3) < 0) break;
            bytes.push(
              codePoint >> 12 | 224,
              codePoint >> 6 & 63 | 128,
              codePoint & 63 | 128
            );
          } else if (codePoint < 1114112) {
            if ((units -= 4) < 0) break;
            bytes.push(
              codePoint >> 18 | 240,
              codePoint >> 12 & 63 | 128,
              codePoint >> 6 & 63 | 128,
              codePoint & 63 | 128
            );
          } else {
            throw new Error("Invalid code point");
          }
        }
        return bytes;
      }
      function asciiToBytes(str) {
        const byteArray = [];
        for (let i = 0; i < str.length; ++i) {
          byteArray.push(str.charCodeAt(i) & 255);
        }
        return byteArray;
      }
      function utf16leToBytes(str, units) {
        let c, hi, lo;
        const byteArray = [];
        for (let i = 0; i < str.length; ++i) {
          if ((units -= 2) < 0) break;
          c = str.charCodeAt(i);
          hi = c >> 8;
          lo = c % 256;
          byteArray.push(lo);
          byteArray.push(hi);
        }
        return byteArray;
      }
      function base64ToBytes(str) {
        return base64.toByteArray(base64clean(str));
      }
      function blitBuffer(src, dst, offset, length) {
        let i;
        for (i = 0; i < length; ++i) {
          if (i + offset >= dst.length || i >= src.length) break;
          dst[i + offset] = src[i];
        }
        return i;
      }
      function isInstance(obj, type) {
        return obj instanceof type || obj != null && obj.constructor != null && obj.constructor.name != null && obj.constructor.name === type.name;
      }
      function numberIsNaN(obj) {
        return obj !== obj;
      }
      var hexSliceLookupTable = (function() {
        const alphabet = "0123456789abcdef";
        const table = new Array(256);
        for (let i = 0; i < 16; ++i) {
          const i16 = i * 16;
          for (let j = 0; j < 16; ++j) {
            table[i16 + j] = alphabet[i] + alphabet[j];
          }
        }
        return table;
      })();
      function defineBigIntMethod(fn) {
        return typeof BigInt === "undefined" ? BufferBigIntNotDefined : fn;
      }
      function BufferBigIntNotDefined() {
        throw new Error("BigInt not supported");
      }
    }
  });

  // (disabled):node_modules/buffer/index.js
  var require_buffer2 = __commonJS({
    "(disabled):node_modules/buffer/index.js"() {
    }
  });

  // node_modules/js-md5/src/md5.js
  var require_md5 = __commonJS({
    "node_modules/js-md5/src/md5.js"(exports, module) {
      (function() {
        "use strict";
        var FEATURE_LEGACY = true;
        var FEATURE_HMAC = true;
        var FEATURE_BASE64 = true;
        var FEATURE_BUFFER = true;
        var INPUT_ERROR = "input is invalid type";
        var FINALIZE_ERROR = "finalize already called";
        var WINDOW = typeof window === "object";
        var root = WINDOW ? window : {};
        if (root.JS_MD5_NO_WINDOW) {
          WINDOW = false;
        }
        var WEB_WORKER = typeof WorkerGlobalScope !== "undefined" && typeof self !== "undefined" && self instanceof WorkerGlobalScope;
        var NODE_JS = !root.JS_MD5_NO_NODE_JS && !WINDOW && typeof process === "object" && process.versions && process.versions.node;
        if (NODE_JS) {
          root = global;
        } else if (WEB_WORKER) {
          root = self;
        }
        var COMMON_JS = !root.JS_MD5_NO_COMMON_JS && typeof module === "object" && module.exports;
        var AMD = typeof define === "function" && define.amd;
        var ARRAY_BUFFER = FEATURE_LEGACY ? !root.JS_MD5_NO_ARRAY_BUFFER && typeof ArrayBuffer !== "undefined" : true;
        var HEX_CHARS = "0123456789abcdef".split("");
        var EXTRA = [128, 32768, 8388608, -2147483648];
        var SHIFT = [0, 8, 16, 24];
        var OUTPUT_TYPES = ["hex", "array", "digest", "arrayBuffer"];
        if (FEATURE_BUFFER) {
          OUTPUT_TYPES.push("buffer");
        }
        if (FEATURE_BASE64) {
          OUTPUT_TYPES.push("base64");
        }
        var BASE64_ENCODE_CHAR = FEATURE_BASE64 ? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".split("") : null;
        var blocks = [], buffer8;
        if (ARRAY_BUFFER) {
          var buffer = new ArrayBuffer(68);
          buffer8 = new Uint8Array(buffer);
          blocks = new Uint32Array(buffer);
        }
        var isArray = Array.isArray;
        if (FEATURE_LEGACY && (root.JS_MD5_NO_NODE_JS || !isArray)) {
          isArray = function(obj) {
            return Object.prototype.toString.call(obj) === "[object Array]";
          };
        }
        var isView = ARRAY_BUFFER ? ArrayBuffer.isView : null;
        if (FEATURE_LEGACY && ARRAY_BUFFER && (root.JS_MD5_NO_ARRAY_BUFFER_IS_VIEW || !isView)) {
          isView = function(obj) {
            return typeof obj === "object" && obj.buffer && obj.buffer.constructor === ArrayBuffer;
          };
        }
        var formatMessage = function(message) {
          var type = typeof message;
          if (type === "string") {
            return [message, true];
          }
          if (type !== "object" || message === null) {
            throw new Error(INPUT_ERROR);
          }
          if (ARRAY_BUFFER && message.constructor === ArrayBuffer) {
            return [new Uint8Array(message), false];
          }
          if (isArray(message)) {
            return [message, false];
          }
          if (!ARRAY_BUFFER || !isView(message)) {
            throw new Error(INPUT_ERROR);
          }
          return [new Uint8Array(message.buffer, message.byteOffset, message.byteLength), false];
        };
        var createOutputMethod = function(outputType) {
          return function(message) {
            return new Md5(true).update(message)[outputType]();
          };
        };
        var createMethod = function() {
          var method = createOutputMethod("hex");
          if (NODE_JS) {
            method = nodeWrap(method);
          }
          method.create = function() {
            return new Md5();
          };
          method.update = function(message) {
            return method.create().update(message);
          };
          for (var i = 0; i < OUTPUT_TYPES.length; ++i) {
            var type = OUTPUT_TYPES[i];
            method[type] = createOutputMethod(type);
          }
          return method;
        };
        var nodeWrap = function(method) {
          var crypto = require_shim_crypto();
          var Buffer2 = require_buffer2().Buffer;
          var bufferFrom = Buffer2.from;
          if (FEATURE_LEGACY && (root.JS_MD5_NO_BUFFER_FROM || !bufferFrom)) {
            bufferFrom = function(message) {
              return new Buffer2(message);
            };
          }
          var nodeMethod = function(message) {
            if (typeof message === "string") {
              return crypto.createHash("md5").update(message, "utf8").digest("hex");
            } else {
              if (message === null || message === void 0) {
                throw new Error(INPUT_ERROR);
              } else if (message.constructor === ArrayBuffer) {
                message = new Uint8Array(message);
              } else if (ARRAY_BUFFER && isView(message) && message.constructor !== Buffer2) {
                message = new Uint8Array(message.buffer, message.byteOffset, message.byteLength);
              }
            }
            if (isArray(message) || isView(message) || message.constructor === Buffer2) {
              return crypto.createHash("md5").update(bufferFrom(message)).digest("hex");
            } else {
              return method(message);
            }
          };
          return nodeMethod;
        };
        var createHmacOutputMethod = function(outputType) {
          return function(key, message) {
            return new HmacMd5(key, true).update(message)[outputType]();
          };
        };
        var createHmacMethod = function() {
          var method = createHmacOutputMethod("hex");
          method.create = function(key) {
            return new HmacMd5(key);
          };
          method.update = function(key, message) {
            return method.create(key).update(message);
          };
          for (var i = 0; i < OUTPUT_TYPES.length; ++i) {
            var type = OUTPUT_TYPES[i];
            method[type] = createHmacOutputMethod(type);
          }
          return method;
        };
        function Md5(sharedMemory) {
          if (sharedMemory) {
            blocks[0] = blocks[16] = blocks[1] = blocks[2] = blocks[3] = blocks[4] = blocks[5] = blocks[6] = blocks[7] = blocks[8] = blocks[9] = blocks[10] = blocks[11] = blocks[12] = blocks[13] = blocks[14] = blocks[15] = 0;
            this.blocks = blocks;
            this.buffer8 = buffer8;
          } else {
            if (ARRAY_BUFFER) {
              var buffer2 = new ArrayBuffer(68);
              this.buffer8 = new Uint8Array(buffer2);
              this.blocks = new Uint32Array(buffer2);
            } else {
              this.blocks = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
            }
          }
          this.h0 = this.h1 = this.h2 = this.h3 = this.start = this.bytes = this.hBytes = 0;
          this.finalized = this.hashed = false;
          this.first = true;
        }
        Md5.prototype.update = function(message) {
          if (this.finalized) {
            throw new Error(FINALIZE_ERROR);
          }
          var result = formatMessage(message);
          message = result[0];
          var isString = result[1];
          var code, code2, index = 0, i, length = message.length, blocks2 = this.blocks;
          var buffer82 = this.buffer8;
          while (index < length) {
            if (this.hashed) {
              this.hashed = false;
              blocks2[0] = blocks2[16];
              blocks2[16] = blocks2[1] = blocks2[2] = blocks2[3] = blocks2[4] = blocks2[5] = blocks2[6] = blocks2[7] = blocks2[8] = blocks2[9] = blocks2[10] = blocks2[11] = blocks2[12] = blocks2[13] = blocks2[14] = blocks2[15] = 0;
            }
            if (isString) {
              if (ARRAY_BUFFER) {
                for (i = this.start; index < length && i < 64; ++index) {
                  code = message.charCodeAt(index);
                  if (code < 128) {
                    buffer82[i++] = code;
                  } else if (code < 2048) {
                    buffer82[i++] = 192 | code >>> 6;
                    buffer82[i++] = 128 | code & 63;
                  } else if (code < 55296 || code >= 57344) {
                    buffer82[i++] = 224 | code >>> 12;
                    buffer82[i++] = 128 | code >>> 6 & 63;
                    buffer82[i++] = 128 | code & 63;
                  } else if (code < 56320 && (code2 = message.charCodeAt(index + 1)) >= 56320 && code2 < 57344) {
                    ++index;
                    code = 65536 + ((code & 1023) << 10 | code2 & 1023);
                    buffer82[i++] = 240 | code >>> 18;
                    buffer82[i++] = 128 | code >>> 12 & 63;
                    buffer82[i++] = 128 | code >>> 6 & 63;
                    buffer82[i++] = 128 | code & 63;
                  } else {
                    buffer82[i++] = 239;
                    buffer82[i++] = 191;
                    buffer82[i++] = 189;
                  }
                }
              } else {
                for (i = this.start; index < length && i < 64; ++index) {
                  code = message.charCodeAt(index);
                  if (code < 128) {
                    blocks2[i >>> 2] |= code << SHIFT[i++ & 3];
                  } else if (code < 2048) {
                    blocks2[i >>> 2] |= (192 | code >>> 6) << SHIFT[i++ & 3];
                    blocks2[i >>> 2] |= (128 | code & 63) << SHIFT[i++ & 3];
                  } else if (code < 55296 || code >= 57344) {
                    blocks2[i >>> 2] |= (224 | code >>> 12) << SHIFT[i++ & 3];
                    blocks2[i >>> 2] |= (128 | code >>> 6 & 63) << SHIFT[i++ & 3];
                    blocks2[i >>> 2] |= (128 | code & 63) << SHIFT[i++ & 3];
                  } else if (code < 56320 && (code2 = message.charCodeAt(index + 1)) >= 56320 && code2 < 57344) {
                    ++index;
                    code = 65536 + ((code & 1023) << 10 | code2 & 1023);
                    blocks2[i >>> 2] |= (240 | code >>> 18) << SHIFT[i++ & 3];
                    blocks2[i >>> 2] |= (128 | code >>> 12 & 63) << SHIFT[i++ & 3];
                    blocks2[i >>> 2] |= (128 | code >>> 6 & 63) << SHIFT[i++ & 3];
                    blocks2[i >>> 2] |= (128 | code & 63) << SHIFT[i++ & 3];
                  } else {
                    blocks2[i >>> 2] |= 239 << SHIFT[i++ & 3];
                    blocks2[i >>> 2] |= 191 << SHIFT[i++ & 3];
                    blocks2[i >>> 2] |= 189 << SHIFT[i++ & 3];
                  }
                }
              }
            } else {
              if (ARRAY_BUFFER) {
                for (i = this.start; index < length && i < 64; ++index) {
                  buffer82[i++] = message[index];
                }
              } else {
                for (i = this.start; index < length && i < 64; ++index) {
                  blocks2[i >>> 2] |= message[index] << SHIFT[i++ & 3];
                }
              }
            }
            this.lastByteIndex = i;
            this.bytes += i - this.start;
            if (i >= 64) {
              this.start = i - 64;
              this.hash();
              this.hashed = true;
            } else {
              this.start = i;
            }
          }
          if (this.bytes > 4294967295) {
            this.hBytes += this.bytes / 4294967296 << 0;
            this.bytes = this.bytes % 4294967296;
          }
          return this;
        };
        Md5.prototype.finalize = function() {
          if (this.finalized) {
            return;
          }
          this.finalized = true;
          var blocks2 = this.blocks, i = this.lastByteIndex;
          blocks2[i >>> 2] |= EXTRA[i & 3];
          if (i >= 56) {
            if (!this.hashed) {
              this.hash();
            }
            blocks2[0] = blocks2[16];
            blocks2[16] = blocks2[1] = blocks2[2] = blocks2[3] = blocks2[4] = blocks2[5] = blocks2[6] = blocks2[7] = blocks2[8] = blocks2[9] = blocks2[10] = blocks2[11] = blocks2[12] = blocks2[13] = blocks2[14] = blocks2[15] = 0;
          }
          blocks2[14] = this.bytes << 3;
          blocks2[15] = this.hBytes << 3 | this.bytes >>> 29;
          this.hash();
        };
        Md5.prototype.hash = function() {
          var a, b, c, d, bc, da, blocks2 = this.blocks;
          if (this.first) {
            a = blocks2[0] - 680876937;
            a = (a << 7 | a >>> 25) - 271733879 << 0;
            d = (-1732584194 ^ a & 2004318071) + blocks2[1] - 117830708;
            d = (d << 12 | d >>> 20) + a << 0;
            c = (-271733879 ^ d & (a ^ -271733879)) + blocks2[2] - 1126478375;
            c = (c << 17 | c >>> 15) + d << 0;
            b = (a ^ c & (d ^ a)) + blocks2[3] - 1316259209;
            b = (b << 22 | b >>> 10) + c << 0;
          } else {
            a = this.h0;
            b = this.h1;
            c = this.h2;
            d = this.h3;
            a += (d ^ b & (c ^ d)) + blocks2[0] - 680876936;
            a = (a << 7 | a >>> 25) + b << 0;
            d += (c ^ a & (b ^ c)) + blocks2[1] - 389564586;
            d = (d << 12 | d >>> 20) + a << 0;
            c += (b ^ d & (a ^ b)) + blocks2[2] + 606105819;
            c = (c << 17 | c >>> 15) + d << 0;
            b += (a ^ c & (d ^ a)) + blocks2[3] - 1044525330;
            b = (b << 22 | b >>> 10) + c << 0;
          }
          a += (d ^ b & (c ^ d)) + blocks2[4] - 176418897;
          a = (a << 7 | a >>> 25) + b << 0;
          d += (c ^ a & (b ^ c)) + blocks2[5] + 1200080426;
          d = (d << 12 | d >>> 20) + a << 0;
          c += (b ^ d & (a ^ b)) + blocks2[6] - 1473231341;
          c = (c << 17 | c >>> 15) + d << 0;
          b += (a ^ c & (d ^ a)) + blocks2[7] - 45705983;
          b = (b << 22 | b >>> 10) + c << 0;
          a += (d ^ b & (c ^ d)) + blocks2[8] + 1770035416;
          a = (a << 7 | a >>> 25) + b << 0;
          d += (c ^ a & (b ^ c)) + blocks2[9] - 1958414417;
          d = (d << 12 | d >>> 20) + a << 0;
          c += (b ^ d & (a ^ b)) + blocks2[10] - 42063;
          c = (c << 17 | c >>> 15) + d << 0;
          b += (a ^ c & (d ^ a)) + blocks2[11] - 1990404162;
          b = (b << 22 | b >>> 10) + c << 0;
          a += (d ^ b & (c ^ d)) + blocks2[12] + 1804603682;
          a = (a << 7 | a >>> 25) + b << 0;
          d += (c ^ a & (b ^ c)) + blocks2[13] - 40341101;
          d = (d << 12 | d >>> 20) + a << 0;
          c += (b ^ d & (a ^ b)) + blocks2[14] - 1502002290;
          c = (c << 17 | c >>> 15) + d << 0;
          b += (a ^ c & (d ^ a)) + blocks2[15] + 1236535329;
          b = (b << 22 | b >>> 10) + c << 0;
          a += (c ^ d & (b ^ c)) + blocks2[1] - 165796510;
          a = (a << 5 | a >>> 27) + b << 0;
          d += (b ^ c & (a ^ b)) + blocks2[6] - 1069501632;
          d = (d << 9 | d >>> 23) + a << 0;
          c += (a ^ b & (d ^ a)) + blocks2[11] + 643717713;
          c = (c << 14 | c >>> 18) + d << 0;
          b += (d ^ a & (c ^ d)) + blocks2[0] - 373897302;
          b = (b << 20 | b >>> 12) + c << 0;
          a += (c ^ d & (b ^ c)) + blocks2[5] - 701558691;
          a = (a << 5 | a >>> 27) + b << 0;
          d += (b ^ c & (a ^ b)) + blocks2[10] + 38016083;
          d = (d << 9 | d >>> 23) + a << 0;
          c += (a ^ b & (d ^ a)) + blocks2[15] - 660478335;
          c = (c << 14 | c >>> 18) + d << 0;
          b += (d ^ a & (c ^ d)) + blocks2[4] - 405537848;
          b = (b << 20 | b >>> 12) + c << 0;
          a += (c ^ d & (b ^ c)) + blocks2[9] + 568446438;
          a = (a << 5 | a >>> 27) + b << 0;
          d += (b ^ c & (a ^ b)) + blocks2[14] - 1019803690;
          d = (d << 9 | d >>> 23) + a << 0;
          c += (a ^ b & (d ^ a)) + blocks2[3] - 187363961;
          c = (c << 14 | c >>> 18) + d << 0;
          b += (d ^ a & (c ^ d)) + blocks2[8] + 1163531501;
          b = (b << 20 | b >>> 12) + c << 0;
          a += (c ^ d & (b ^ c)) + blocks2[13] - 1444681467;
          a = (a << 5 | a >>> 27) + b << 0;
          d += (b ^ c & (a ^ b)) + blocks2[2] - 51403784;
          d = (d << 9 | d >>> 23) + a << 0;
          c += (a ^ b & (d ^ a)) + blocks2[7] + 1735328473;
          c = (c << 14 | c >>> 18) + d << 0;
          b += (d ^ a & (c ^ d)) + blocks2[12] - 1926607734;
          b = (b << 20 | b >>> 12) + c << 0;
          bc = b ^ c;
          a += (bc ^ d) + blocks2[5] - 378558;
          a = (a << 4 | a >>> 28) + b << 0;
          d += (bc ^ a) + blocks2[8] - 2022574463;
          d = (d << 11 | d >>> 21) + a << 0;
          da = d ^ a;
          c += (da ^ b) + blocks2[11] + 1839030562;
          c = (c << 16 | c >>> 16) + d << 0;
          b += (da ^ c) + blocks2[14] - 35309556;
          b = (b << 23 | b >>> 9) + c << 0;
          bc = b ^ c;
          a += (bc ^ d) + blocks2[1] - 1530992060;
          a = (a << 4 | a >>> 28) + b << 0;
          d += (bc ^ a) + blocks2[4] + 1272893353;
          d = (d << 11 | d >>> 21) + a << 0;
          da = d ^ a;
          c += (da ^ b) + blocks2[7] - 155497632;
          c = (c << 16 | c >>> 16) + d << 0;
          b += (da ^ c) + blocks2[10] - 1094730640;
          b = (b << 23 | b >>> 9) + c << 0;
          bc = b ^ c;
          a += (bc ^ d) + blocks2[13] + 681279174;
          a = (a << 4 | a >>> 28) + b << 0;
          d += (bc ^ a) + blocks2[0] - 358537222;
          d = (d << 11 | d >>> 21) + a << 0;
          da = d ^ a;
          c += (da ^ b) + blocks2[3] - 722521979;
          c = (c << 16 | c >>> 16) + d << 0;
          b += (da ^ c) + blocks2[6] + 76029189;
          b = (b << 23 | b >>> 9) + c << 0;
          bc = b ^ c;
          a += (bc ^ d) + blocks2[9] - 640364487;
          a = (a << 4 | a >>> 28) + b << 0;
          d += (bc ^ a) + blocks2[12] - 421815835;
          d = (d << 11 | d >>> 21) + a << 0;
          da = d ^ a;
          c += (da ^ b) + blocks2[15] + 530742520;
          c = (c << 16 | c >>> 16) + d << 0;
          b += (da ^ c) + blocks2[2] - 995338651;
          b = (b << 23 | b >>> 9) + c << 0;
          a += (c ^ (b | ~d)) + blocks2[0] - 198630844;
          a = (a << 6 | a >>> 26) + b << 0;
          d += (b ^ (a | ~c)) + blocks2[7] + 1126891415;
          d = (d << 10 | d >>> 22) + a << 0;
          c += (a ^ (d | ~b)) + blocks2[14] - 1416354905;
          c = (c << 15 | c >>> 17) + d << 0;
          b += (d ^ (c | ~a)) + blocks2[5] - 57434055;
          b = (b << 21 | b >>> 11) + c << 0;
          a += (c ^ (b | ~d)) + blocks2[12] + 1700485571;
          a = (a << 6 | a >>> 26) + b << 0;
          d += (b ^ (a | ~c)) + blocks2[3] - 1894986606;
          d = (d << 10 | d >>> 22) + a << 0;
          c += (a ^ (d | ~b)) + blocks2[10] - 1051523;
          c = (c << 15 | c >>> 17) + d << 0;
          b += (d ^ (c | ~a)) + blocks2[1] - 2054922799;
          b = (b << 21 | b >>> 11) + c << 0;
          a += (c ^ (b | ~d)) + blocks2[8] + 1873313359;
          a = (a << 6 | a >>> 26) + b << 0;
          d += (b ^ (a | ~c)) + blocks2[15] - 30611744;
          d = (d << 10 | d >>> 22) + a << 0;
          c += (a ^ (d | ~b)) + blocks2[6] - 1560198380;
          c = (c << 15 | c >>> 17) + d << 0;
          b += (d ^ (c | ~a)) + blocks2[13] + 1309151649;
          b = (b << 21 | b >>> 11) + c << 0;
          a += (c ^ (b | ~d)) + blocks2[4] - 145523070;
          a = (a << 6 | a >>> 26) + b << 0;
          d += (b ^ (a | ~c)) + blocks2[11] - 1120210379;
          d = (d << 10 | d >>> 22) + a << 0;
          c += (a ^ (d | ~b)) + blocks2[2] + 718787259;
          c = (c << 15 | c >>> 17) + d << 0;
          b += (d ^ (c | ~a)) + blocks2[9] - 343485551;
          b = (b << 21 | b >>> 11) + c << 0;
          if (this.first) {
            this.h0 = a + 1732584193 << 0;
            this.h1 = b - 271733879 << 0;
            this.h2 = c - 1732584194 << 0;
            this.h3 = d + 271733878 << 0;
            this.first = false;
          } else {
            this.h0 = this.h0 + a << 0;
            this.h1 = this.h1 + b << 0;
            this.h2 = this.h2 + c << 0;
            this.h3 = this.h3 + d << 0;
          }
        };
        Md5.prototype.hex = function() {
          this.finalize();
          var h0 = this.h0, h1 = this.h1, h2 = this.h2, h3 = this.h3;
          return HEX_CHARS[h0 >>> 4 & 15] + HEX_CHARS[h0 & 15] + HEX_CHARS[h0 >>> 12 & 15] + HEX_CHARS[h0 >>> 8 & 15] + HEX_CHARS[h0 >>> 20 & 15] + HEX_CHARS[h0 >>> 16 & 15] + HEX_CHARS[h0 >>> 28 & 15] + HEX_CHARS[h0 >>> 24 & 15] + HEX_CHARS[h1 >>> 4 & 15] + HEX_CHARS[h1 & 15] + HEX_CHARS[h1 >>> 12 & 15] + HEX_CHARS[h1 >>> 8 & 15] + HEX_CHARS[h1 >>> 20 & 15] + HEX_CHARS[h1 >>> 16 & 15] + HEX_CHARS[h1 >>> 28 & 15] + HEX_CHARS[h1 >>> 24 & 15] + HEX_CHARS[h2 >>> 4 & 15] + HEX_CHARS[h2 & 15] + HEX_CHARS[h2 >>> 12 & 15] + HEX_CHARS[h2 >>> 8 & 15] + HEX_CHARS[h2 >>> 20 & 15] + HEX_CHARS[h2 >>> 16 & 15] + HEX_CHARS[h2 >>> 28 & 15] + HEX_CHARS[h2 >>> 24 & 15] + HEX_CHARS[h3 >>> 4 & 15] + HEX_CHARS[h3 & 15] + HEX_CHARS[h3 >>> 12 & 15] + HEX_CHARS[h3 >>> 8 & 15] + HEX_CHARS[h3 >>> 20 & 15] + HEX_CHARS[h3 >>> 16 & 15] + HEX_CHARS[h3 >>> 28 & 15] + HEX_CHARS[h3 >>> 24 & 15];
        };
        Md5.prototype.toString = Md5.prototype.hex;
        Md5.prototype.digest = function() {
          this.finalize();
          var h0 = this.h0, h1 = this.h1, h2 = this.h2, h3 = this.h3;
          return [
            h0 & 255,
            h0 >>> 8 & 255,
            h0 >>> 16 & 255,
            h0 >>> 24 & 255,
            h1 & 255,
            h1 >>> 8 & 255,
            h1 >>> 16 & 255,
            h1 >>> 24 & 255,
            h2 & 255,
            h2 >>> 8 & 255,
            h2 >>> 16 & 255,
            h2 >>> 24 & 255,
            h3 & 255,
            h3 >>> 8 & 255,
            h3 >>> 16 & 255,
            h3 >>> 24 & 255
          ];
        };
        Md5.prototype.array = Md5.prototype.digest;
        Md5.prototype.arrayBuffer = function() {
          this.finalize();
          var buffer2 = new ArrayBuffer(16);
          var blocks2 = new Uint32Array(buffer2);
          blocks2[0] = this.h0;
          blocks2[1] = this.h1;
          blocks2[2] = this.h2;
          blocks2[3] = this.h3;
          return buffer2;
        };
        if (FEATURE_BUFFER) {
          Md5.prototype.buffer = Md5.prototype.arrayBuffer;
        }
        if (FEATURE_BASE64) {
          Md5.prototype.base64 = function() {
            var v1, v2, v3, base64Str = "", bytes = this.array();
            for (var i = 0; i < 15; ) {
              v1 = bytes[i++];
              v2 = bytes[i++];
              v3 = bytes[i++];
              base64Str += BASE64_ENCODE_CHAR[v1 >>> 2] + BASE64_ENCODE_CHAR[(v1 << 4 | v2 >>> 4) & 63] + BASE64_ENCODE_CHAR[(v2 << 2 | v3 >>> 6) & 63] + BASE64_ENCODE_CHAR[v3 & 63];
            }
            v1 = bytes[i];
            base64Str += BASE64_ENCODE_CHAR[v1 >>> 2] + BASE64_ENCODE_CHAR[v1 << 4 & 63] + "==";
            return base64Str;
          };
        }
        function HmacMd5(key, sharedMemory) {
          var i, result = formatMessage(key);
          key = result[0];
          if (result[1]) {
            var bytes = [], length = key.length, index = 0, code, code2;
            for (i = 0; i < length; ++i) {
              code = key.charCodeAt(i);
              if (code < 128) {
                bytes[index++] = code;
              } else if (code < 2048) {
                bytes[index++] = 192 | code >>> 6;
                bytes[index++] = 128 | code & 63;
              } else if (code < 55296 || code >= 57344) {
                bytes[index++] = 224 | code >>> 12;
                bytes[index++] = 128 | code >>> 6 & 63;
                bytes[index++] = 128 | code & 63;
              } else if (code < 56320 && (code2 = key.charCodeAt(i + 1)) >= 56320 && code2 < 57344) {
                ++i;
                code = 65536 + ((code & 1023) << 10 | code2 & 1023);
                bytes[index++] = 240 | code >>> 18;
                bytes[index++] = 128 | code >>> 12 & 63;
                bytes[index++] = 128 | code >>> 6 & 63;
                bytes[index++] = 128 | code & 63;
              } else {
                bytes[index++] = 239;
                bytes[index++] = 191;
                bytes[index++] = 189;
              }
            }
            key = bytes;
          }
          if (key.length > 64) {
            key = new Md5(true).update(key).array();
          }
          var oKeyPad = [], iKeyPad = [];
          for (i = 0; i < 64; ++i) {
            var b = key[i] || 0;
            oKeyPad[i] = 92 ^ b;
            iKeyPad[i] = 54 ^ b;
          }
          Md5.call(this, sharedMemory);
          this.update(iKeyPad);
          this.oKeyPad = oKeyPad;
          this.inner = true;
          this.sharedMemory = sharedMemory;
        }
        if (FEATURE_HMAC) {
          HmacMd5.prototype = new Md5();
          HmacMd5.prototype.finalize = function() {
            Md5.prototype.finalize.call(this);
            if (this.inner) {
              this.inner = false;
              var innerHash = this.array();
              Md5.call(this, this.sharedMemory);
              this.update(this.oKeyPad);
              this.update(innerHash);
              Md5.prototype.finalize.call(this);
            }
          };
        }
        var exports2 = createMethod();
        exports2.md5 = exports2;
        if (FEATURE_HMAC) {
          exports2.md5.hmac = createHmacMethod();
        }
        if (COMMON_JS) {
          module.exports = exports2;
        } else {
          root.md5 = exports2;
          if (AMD) {
            define(function() {
              return exports2;
            });
          }
        }
      })();
    }
  });

  // node_modules/jsbn/index.js
  var require_jsbn = __commonJS({
    "node_modules/jsbn/index.js"(exports, module) {
      (function() {
        var dbits;
        var canary = 244837814094590;
        var j_lm = (canary & 16777215) == 15715070;
        function BigInteger(a, b, c) {
          if (a != null)
            if ("number" == typeof a) this.fromNumber(a, b, c);
            else if (b == null && "string" != typeof a) this.fromString(a, 256);
            else this.fromString(a, b);
        }
        function nbi() {
          return new BigInteger(null);
        }
        function am1(i, x, w, j, c, n) {
          while (--n >= 0) {
            var v = x * this[i++] + w[j] + c;
            c = Math.floor(v / 67108864);
            w[j++] = v & 67108863;
          }
          return c;
        }
        function am2(i, x, w, j, c, n) {
          var xl = x & 32767, xh = x >> 15;
          while (--n >= 0) {
            var l = this[i] & 32767;
            var h = this[i++] >> 15;
            var m = xh * l + h * xl;
            l = xl * l + ((m & 32767) << 15) + w[j] + (c & 1073741823);
            c = (l >>> 30) + (m >>> 15) + xh * h + (c >>> 30);
            w[j++] = l & 1073741823;
          }
          return c;
        }
        function am3(i, x, w, j, c, n) {
          var xl = x & 16383, xh = x >> 14;
          while (--n >= 0) {
            var l = this[i] & 16383;
            var h = this[i++] >> 14;
            var m = xh * l + h * xl;
            l = xl * l + ((m & 16383) << 14) + w[j] + c;
            c = (l >> 28) + (m >> 14) + xh * h;
            w[j++] = l & 268435455;
          }
          return c;
        }
        var inBrowser = typeof navigator !== "undefined";
        if (inBrowser && j_lm && navigator.appName == "Microsoft Internet Explorer") {
          BigInteger.prototype.am = am2;
          dbits = 30;
        } else if (inBrowser && j_lm && navigator.appName != "Netscape") {
          BigInteger.prototype.am = am1;
          dbits = 26;
        } else {
          BigInteger.prototype.am = am3;
          dbits = 28;
        }
        BigInteger.prototype.DB = dbits;
        BigInteger.prototype.DM = (1 << dbits) - 1;
        BigInteger.prototype.DV = 1 << dbits;
        var BI_FP = 52;
        BigInteger.prototype.FV = Math.pow(2, BI_FP);
        BigInteger.prototype.F1 = BI_FP - dbits;
        BigInteger.prototype.F2 = 2 * dbits - BI_FP;
        var BI_RM = "0123456789abcdefghijklmnopqrstuvwxyz";
        var BI_RC = new Array();
        var rr, vv;
        rr = "0".charCodeAt(0);
        for (vv = 0; vv <= 9; ++vv) BI_RC[rr++] = vv;
        rr = "a".charCodeAt(0);
        for (vv = 10; vv < 36; ++vv) BI_RC[rr++] = vv;
        rr = "A".charCodeAt(0);
        for (vv = 10; vv < 36; ++vv) BI_RC[rr++] = vv;
        function int2char(n) {
          return BI_RM.charAt(n);
        }
        function intAt(s, i) {
          var c = BI_RC[s.charCodeAt(i)];
          return c == null ? -1 : c;
        }
        function bnpCopyTo(r) {
          for (var i = this.t - 1; i >= 0; --i) r[i] = this[i];
          r.t = this.t;
          r.s = this.s;
        }
        function bnpFromInt(x) {
          this.t = 1;
          this.s = x < 0 ? -1 : 0;
          if (x > 0) this[0] = x;
          else if (x < -1) this[0] = x + this.DV;
          else this.t = 0;
        }
        function nbv(i) {
          var r = nbi();
          r.fromInt(i);
          return r;
        }
        function bnpFromString(s, b) {
          var k;
          if (b == 16) k = 4;
          else if (b == 8) k = 3;
          else if (b == 256) k = 8;
          else if (b == 2) k = 1;
          else if (b == 32) k = 5;
          else if (b == 4) k = 2;
          else {
            this.fromRadix(s, b);
            return;
          }
          this.t = 0;
          this.s = 0;
          var i = s.length, mi = false, sh = 0;
          while (--i >= 0) {
            var x = k == 8 ? s[i] & 255 : intAt(s, i);
            if (x < 0) {
              if (s.charAt(i) == "-") mi = true;
              continue;
            }
            mi = false;
            if (sh == 0)
              this[this.t++] = x;
            else if (sh + k > this.DB) {
              this[this.t - 1] |= (x & (1 << this.DB - sh) - 1) << sh;
              this[this.t++] = x >> this.DB - sh;
            } else
              this[this.t - 1] |= x << sh;
            sh += k;
            if (sh >= this.DB) sh -= this.DB;
          }
          if (k == 8 && (s[0] & 128) != 0) {
            this.s = -1;
            if (sh > 0) this[this.t - 1] |= (1 << this.DB - sh) - 1 << sh;
          }
          this.clamp();
          if (mi) BigInteger.ZERO.subTo(this, this);
        }
        function bnpClamp() {
          var c = this.s & this.DM;
          while (this.t > 0 && this[this.t - 1] == c) --this.t;
        }
        function bnToString(b) {
          if (this.s < 0) return "-" + this.negate().toString(b);
          var k;
          if (b == 16) k = 4;
          else if (b == 8) k = 3;
          else if (b == 2) k = 1;
          else if (b == 32) k = 5;
          else if (b == 4) k = 2;
          else return this.toRadix(b);
          var km = (1 << k) - 1, d, m = false, r = "", i = this.t;
          var p = this.DB - i * this.DB % k;
          if (i-- > 0) {
            if (p < this.DB && (d = this[i] >> p) > 0) {
              m = true;
              r = int2char(d);
            }
            while (i >= 0) {
              if (p < k) {
                d = (this[i] & (1 << p) - 1) << k - p;
                d |= this[--i] >> (p += this.DB - k);
              } else {
                d = this[i] >> (p -= k) & km;
                if (p <= 0) {
                  p += this.DB;
                  --i;
                }
              }
              if (d > 0) m = true;
              if (m) r += int2char(d);
            }
          }
          return m ? r : "0";
        }
        function bnNegate() {
          var r = nbi();
          BigInteger.ZERO.subTo(this, r);
          return r;
        }
        function bnAbs() {
          return this.s < 0 ? this.negate() : this;
        }
        function bnCompareTo(a) {
          var r = this.s - a.s;
          if (r != 0) return r;
          var i = this.t;
          r = i - a.t;
          if (r != 0) return this.s < 0 ? -r : r;
          while (--i >= 0) if ((r = this[i] - a[i]) != 0) return r;
          return 0;
        }
        function nbits(x) {
          var r = 1, t2;
          if ((t2 = x >>> 16) != 0) {
            x = t2;
            r += 16;
          }
          if ((t2 = x >> 8) != 0) {
            x = t2;
            r += 8;
          }
          if ((t2 = x >> 4) != 0) {
            x = t2;
            r += 4;
          }
          if ((t2 = x >> 2) != 0) {
            x = t2;
            r += 2;
          }
          if ((t2 = x >> 1) != 0) {
            x = t2;
            r += 1;
          }
          return r;
        }
        function bnBitLength() {
          if (this.t <= 0) return 0;
          return this.DB * (this.t - 1) + nbits(this[this.t - 1] ^ this.s & this.DM);
        }
        function bnpDLShiftTo(n, r) {
          var i;
          for (i = this.t - 1; i >= 0; --i) r[i + n] = this[i];
          for (i = n - 1; i >= 0; --i) r[i] = 0;
          r.t = this.t + n;
          r.s = this.s;
        }
        function bnpDRShiftTo(n, r) {
          for (var i = n; i < this.t; ++i) r[i - n] = this[i];
          r.t = Math.max(this.t - n, 0);
          r.s = this.s;
        }
        function bnpLShiftTo(n, r) {
          var bs = n % this.DB;
          var cbs = this.DB - bs;
          var bm = (1 << cbs) - 1;
          var ds = Math.floor(n / this.DB), c = this.s << bs & this.DM, i;
          for (i = this.t - 1; i >= 0; --i) {
            r[i + ds + 1] = this[i] >> cbs | c;
            c = (this[i] & bm) << bs;
          }
          for (i = ds - 1; i >= 0; --i) r[i] = 0;
          r[ds] = c;
          r.t = this.t + ds + 1;
          r.s = this.s;
          r.clamp();
        }
        function bnpRShiftTo(n, r) {
          r.s = this.s;
          var ds = Math.floor(n / this.DB);
          if (ds >= this.t) {
            r.t = 0;
            return;
          }
          var bs = n % this.DB;
          var cbs = this.DB - bs;
          var bm = (1 << bs) - 1;
          r[0] = this[ds] >> bs;
          for (var i = ds + 1; i < this.t; ++i) {
            r[i - ds - 1] |= (this[i] & bm) << cbs;
            r[i - ds] = this[i] >> bs;
          }
          if (bs > 0) r[this.t - ds - 1] |= (this.s & bm) << cbs;
          r.t = this.t - ds;
          r.clamp();
        }
        function bnpSubTo(a, r) {
          var i = 0, c = 0, m = Math.min(a.t, this.t);
          while (i < m) {
            c += this[i] - a[i];
            r[i++] = c & this.DM;
            c >>= this.DB;
          }
          if (a.t < this.t) {
            c -= a.s;
            while (i < this.t) {
              c += this[i];
              r[i++] = c & this.DM;
              c >>= this.DB;
            }
            c += this.s;
          } else {
            c += this.s;
            while (i < a.t) {
              c -= a[i];
              r[i++] = c & this.DM;
              c >>= this.DB;
            }
            c -= a.s;
          }
          r.s = c < 0 ? -1 : 0;
          if (c < -1) r[i++] = this.DV + c;
          else if (c > 0) r[i++] = c;
          r.t = i;
          r.clamp();
        }
        function bnpMultiplyTo(a, r) {
          var x = this.abs(), y = a.abs();
          var i = x.t;
          r.t = i + y.t;
          while (--i >= 0) r[i] = 0;
          for (i = 0; i < y.t; ++i) r[i + x.t] = x.am(0, y[i], r, i, 0, x.t);
          r.s = 0;
          r.clamp();
          if (this.s != a.s) BigInteger.ZERO.subTo(r, r);
        }
        function bnpSquareTo(r) {
          var x = this.abs();
          var i = r.t = 2 * x.t;
          while (--i >= 0) r[i] = 0;
          for (i = 0; i < x.t - 1; ++i) {
            var c = x.am(i, x[i], r, 2 * i, 0, 1);
            if ((r[i + x.t] += x.am(i + 1, 2 * x[i], r, 2 * i + 1, c, x.t - i - 1)) >= x.DV) {
              r[i + x.t] -= x.DV;
              r[i + x.t + 1] = 1;
            }
          }
          if (r.t > 0) r[r.t - 1] += x.am(i, x[i], r, 2 * i, 0, 1);
          r.s = 0;
          r.clamp();
        }
        function bnpDivRemTo(m, q, r) {
          var pm = m.abs();
          if (pm.t <= 0) return;
          var pt = this.abs();
          if (pt.t < pm.t) {
            if (q != null) q.fromInt(0);
            if (r != null) this.copyTo(r);
            return;
          }
          if (r == null) r = nbi();
          var y = nbi(), ts = this.s, ms = m.s;
          var nsh = this.DB - nbits(pm[pm.t - 1]);
          if (nsh > 0) {
            pm.lShiftTo(nsh, y);
            pt.lShiftTo(nsh, r);
          } else {
            pm.copyTo(y);
            pt.copyTo(r);
          }
          var ys = y.t;
          var y0 = y[ys - 1];
          if (y0 == 0) return;
          var yt = y0 * (1 << this.F1) + (ys > 1 ? y[ys - 2] >> this.F2 : 0);
          var d1 = this.FV / yt, d2 = (1 << this.F1) / yt, e = 1 << this.F2;
          var i = r.t, j = i - ys, t2 = q == null ? nbi() : q;
          y.dlShiftTo(j, t2);
          if (r.compareTo(t2) >= 0) {
            r[r.t++] = 1;
            r.subTo(t2, r);
          }
          BigInteger.ONE.dlShiftTo(ys, t2);
          t2.subTo(y, y);
          while (y.t < ys) y[y.t++] = 0;
          while (--j >= 0) {
            var qd = r[--i] == y0 ? this.DM : Math.floor(r[i] * d1 + (r[i - 1] + e) * d2);
            if ((r[i] += y.am(0, qd, r, j, 0, ys)) < qd) {
              y.dlShiftTo(j, t2);
              r.subTo(t2, r);
              while (r[i] < --qd) r.subTo(t2, r);
            }
          }
          if (q != null) {
            r.drShiftTo(ys, q);
            if (ts != ms) BigInteger.ZERO.subTo(q, q);
          }
          r.t = ys;
          r.clamp();
          if (nsh > 0) r.rShiftTo(nsh, r);
          if (ts < 0) BigInteger.ZERO.subTo(r, r);
        }
        function bnMod(a) {
          var r = nbi();
          this.abs().divRemTo(a, null, r);
          if (this.s < 0 && r.compareTo(BigInteger.ZERO) > 0) a.subTo(r, r);
          return r;
        }
        function Classic(m) {
          this.m = m;
        }
        function cConvert(x) {
          if (x.s < 0 || x.compareTo(this.m) >= 0) return x.mod(this.m);
          else return x;
        }
        function cRevert(x) {
          return x;
        }
        function cReduce(x) {
          x.divRemTo(this.m, null, x);
        }
        function cMulTo(x, y, r) {
          x.multiplyTo(y, r);
          this.reduce(r);
        }
        function cSqrTo(x, r) {
          x.squareTo(r);
          this.reduce(r);
        }
        Classic.prototype.convert = cConvert;
        Classic.prototype.revert = cRevert;
        Classic.prototype.reduce = cReduce;
        Classic.prototype.mulTo = cMulTo;
        Classic.prototype.sqrTo = cSqrTo;
        function bnpInvDigit() {
          if (this.t < 1) return 0;
          var x = this[0];
          if ((x & 1) == 0) return 0;
          var y = x & 3;
          y = y * (2 - (x & 15) * y) & 15;
          y = y * (2 - (x & 255) * y) & 255;
          y = y * (2 - ((x & 65535) * y & 65535)) & 65535;
          y = y * (2 - x * y % this.DV) % this.DV;
          return y > 0 ? this.DV - y : -y;
        }
        function Montgomery(m) {
          this.m = m;
          this.mp = m.invDigit();
          this.mpl = this.mp & 32767;
          this.mph = this.mp >> 15;
          this.um = (1 << m.DB - 15) - 1;
          this.mt2 = 2 * m.t;
        }
        function montConvert(x) {
          var r = nbi();
          x.abs().dlShiftTo(this.m.t, r);
          r.divRemTo(this.m, null, r);
          if (x.s < 0 && r.compareTo(BigInteger.ZERO) > 0) this.m.subTo(r, r);
          return r;
        }
        function montRevert(x) {
          var r = nbi();
          x.copyTo(r);
          this.reduce(r);
          return r;
        }
        function montReduce(x) {
          while (x.t <= this.mt2)
            x[x.t++] = 0;
          for (var i = 0; i < this.m.t; ++i) {
            var j = x[i] & 32767;
            var u0 = j * this.mpl + ((j * this.mph + (x[i] >> 15) * this.mpl & this.um) << 15) & x.DM;
            j = i + this.m.t;
            x[j] += this.m.am(0, u0, x, i, 0, this.m.t);
            while (x[j] >= x.DV) {
              x[j] -= x.DV;
              x[++j]++;
            }
          }
          x.clamp();
          x.drShiftTo(this.m.t, x);
          if (x.compareTo(this.m) >= 0) x.subTo(this.m, x);
        }
        function montSqrTo(x, r) {
          x.squareTo(r);
          this.reduce(r);
        }
        function montMulTo(x, y, r) {
          x.multiplyTo(y, r);
          this.reduce(r);
        }
        Montgomery.prototype.convert = montConvert;
        Montgomery.prototype.revert = montRevert;
        Montgomery.prototype.reduce = montReduce;
        Montgomery.prototype.mulTo = montMulTo;
        Montgomery.prototype.sqrTo = montSqrTo;
        function bnpIsEven() {
          return (this.t > 0 ? this[0] & 1 : this.s) == 0;
        }
        function bnpExp(e, z2) {
          if (e > 4294967295 || e < 1) return BigInteger.ONE;
          var r = nbi(), r2 = nbi(), g = z2.convert(this), i = nbits(e) - 1;
          g.copyTo(r);
          while (--i >= 0) {
            z2.sqrTo(r, r2);
            if ((e & 1 << i) > 0) z2.mulTo(r2, g, r);
            else {
              var t2 = r;
              r = r2;
              r2 = t2;
            }
          }
          return z2.revert(r);
        }
        function bnModPowInt(e, m) {
          var z2;
          if (e < 256 || m.isEven()) z2 = new Classic(m);
          else z2 = new Montgomery(m);
          return this.exp(e, z2);
        }
        BigInteger.prototype.copyTo = bnpCopyTo;
        BigInteger.prototype.fromInt = bnpFromInt;
        BigInteger.prototype.fromString = bnpFromString;
        BigInteger.prototype.clamp = bnpClamp;
        BigInteger.prototype.dlShiftTo = bnpDLShiftTo;
        BigInteger.prototype.drShiftTo = bnpDRShiftTo;
        BigInteger.prototype.lShiftTo = bnpLShiftTo;
        BigInteger.prototype.rShiftTo = bnpRShiftTo;
        BigInteger.prototype.subTo = bnpSubTo;
        BigInteger.prototype.multiplyTo = bnpMultiplyTo;
        BigInteger.prototype.squareTo = bnpSquareTo;
        BigInteger.prototype.divRemTo = bnpDivRemTo;
        BigInteger.prototype.invDigit = bnpInvDigit;
        BigInteger.prototype.isEven = bnpIsEven;
        BigInteger.prototype.exp = bnpExp;
        BigInteger.prototype.toString = bnToString;
        BigInteger.prototype.negate = bnNegate;
        BigInteger.prototype.abs = bnAbs;
        BigInteger.prototype.compareTo = bnCompareTo;
        BigInteger.prototype.bitLength = bnBitLength;
        BigInteger.prototype.mod = bnMod;
        BigInteger.prototype.modPowInt = bnModPowInt;
        BigInteger.ZERO = nbv(0);
        BigInteger.ONE = nbv(1);
        function bnClone() {
          var r = nbi();
          this.copyTo(r);
          return r;
        }
        function bnIntValue() {
          if (this.s < 0) {
            if (this.t == 1) return this[0] - this.DV;
            else if (this.t == 0) return -1;
          } else if (this.t == 1) return this[0];
          else if (this.t == 0) return 0;
          return (this[1] & (1 << 32 - this.DB) - 1) << this.DB | this[0];
        }
        function bnByteValue() {
          return this.t == 0 ? this.s : this[0] << 24 >> 24;
        }
        function bnShortValue() {
          return this.t == 0 ? this.s : this[0] << 16 >> 16;
        }
        function bnpChunkSize(r) {
          return Math.floor(Math.LN2 * this.DB / Math.log(r));
        }
        function bnSigNum() {
          if (this.s < 0) return -1;
          else if (this.t <= 0 || this.t == 1 && this[0] <= 0) return 0;
          else return 1;
        }
        function bnpToRadix(b) {
          if (b == null) b = 10;
          if (this.signum() == 0 || b < 2 || b > 36) return "0";
          var cs = this.chunkSize(b);
          var a = Math.pow(b, cs);
          var d = nbv(a), y = nbi(), z2 = nbi(), r = "";
          this.divRemTo(d, y, z2);
          while (y.signum() > 0) {
            r = (a + z2.intValue()).toString(b).substr(1) + r;
            y.divRemTo(d, y, z2);
          }
          return z2.intValue().toString(b) + r;
        }
        function bnpFromRadix(s, b) {
          this.fromInt(0);
          if (b == null) b = 10;
          var cs = this.chunkSize(b);
          var d = Math.pow(b, cs), mi = false, j = 0, w = 0;
          for (var i = 0; i < s.length; ++i) {
            var x = intAt(s, i);
            if (x < 0) {
              if (s.charAt(i) == "-" && this.signum() == 0) mi = true;
              continue;
            }
            w = b * w + x;
            if (++j >= cs) {
              this.dMultiply(d);
              this.dAddOffset(w, 0);
              j = 0;
              w = 0;
            }
          }
          if (j > 0) {
            this.dMultiply(Math.pow(b, j));
            this.dAddOffset(w, 0);
          }
          if (mi) BigInteger.ZERO.subTo(this, this);
        }
        function bnpFromNumber(a, b, c) {
          if ("number" == typeof b) {
            if (a < 2) this.fromInt(1);
            else {
              this.fromNumber(a, c);
              if (!this.testBit(a - 1))
                this.bitwiseTo(BigInteger.ONE.shiftLeft(a - 1), op_or, this);
              if (this.isEven()) this.dAddOffset(1, 0);
              while (!this.isProbablePrime(b)) {
                this.dAddOffset(2, 0);
                if (this.bitLength() > a) this.subTo(BigInteger.ONE.shiftLeft(a - 1), this);
              }
            }
          } else {
            var x = new Array(), t2 = a & 7;
            x.length = (a >> 3) + 1;
            b.nextBytes(x);
            if (t2 > 0) x[0] &= (1 << t2) - 1;
            else x[0] = 0;
            this.fromString(x, 256);
          }
        }
        function bnToByteArray() {
          var i = this.t, r = new Array();
          r[0] = this.s;
          var p = this.DB - i * this.DB % 8, d, k = 0;
          if (i-- > 0) {
            if (p < this.DB && (d = this[i] >> p) != (this.s & this.DM) >> p)
              r[k++] = d | this.s << this.DB - p;
            while (i >= 0) {
              if (p < 8) {
                d = (this[i] & (1 << p) - 1) << 8 - p;
                d |= this[--i] >> (p += this.DB - 8);
              } else {
                d = this[i] >> (p -= 8) & 255;
                if (p <= 0) {
                  p += this.DB;
                  --i;
                }
              }
              if ((d & 128) != 0) d |= -256;
              if (k == 0 && (this.s & 128) != (d & 128)) ++k;
              if (k > 0 || d != this.s) r[k++] = d;
            }
          }
          return r;
        }
        function bnEquals(a) {
          return this.compareTo(a) == 0;
        }
        function bnMin(a) {
          return this.compareTo(a) < 0 ? this : a;
        }
        function bnMax(a) {
          return this.compareTo(a) > 0 ? this : a;
        }
        function bnpBitwiseTo(a, op, r) {
          var i, f, m = Math.min(a.t, this.t);
          for (i = 0; i < m; ++i) r[i] = op(this[i], a[i]);
          if (a.t < this.t) {
            f = a.s & this.DM;
            for (i = m; i < this.t; ++i) r[i] = op(this[i], f);
            r.t = this.t;
          } else {
            f = this.s & this.DM;
            for (i = m; i < a.t; ++i) r[i] = op(f, a[i]);
            r.t = a.t;
          }
          r.s = op(this.s, a.s);
          r.clamp();
        }
        function op_and(x, y) {
          return x & y;
        }
        function bnAnd(a) {
          var r = nbi();
          this.bitwiseTo(a, op_and, r);
          return r;
        }
        function op_or(x, y) {
          return x | y;
        }
        function bnOr(a) {
          var r = nbi();
          this.bitwiseTo(a, op_or, r);
          return r;
        }
        function op_xor(x, y) {
          return x ^ y;
        }
        function bnXor(a) {
          var r = nbi();
          this.bitwiseTo(a, op_xor, r);
          return r;
        }
        function op_andnot(x, y) {
          return x & ~y;
        }
        function bnAndNot(a) {
          var r = nbi();
          this.bitwiseTo(a, op_andnot, r);
          return r;
        }
        function bnNot() {
          var r = nbi();
          for (var i = 0; i < this.t; ++i) r[i] = this.DM & ~this[i];
          r.t = this.t;
          r.s = ~this.s;
          return r;
        }
        function bnShiftLeft(n) {
          var r = nbi();
          if (n < 0) this.rShiftTo(-n, r);
          else this.lShiftTo(n, r);
          return r;
        }
        function bnShiftRight(n) {
          var r = nbi();
          if (n < 0) this.lShiftTo(-n, r);
          else this.rShiftTo(n, r);
          return r;
        }
        function lbit(x) {
          if (x == 0) return -1;
          var r = 0;
          if ((x & 65535) == 0) {
            x >>= 16;
            r += 16;
          }
          if ((x & 255) == 0) {
            x >>= 8;
            r += 8;
          }
          if ((x & 15) == 0) {
            x >>= 4;
            r += 4;
          }
          if ((x & 3) == 0) {
            x >>= 2;
            r += 2;
          }
          if ((x & 1) == 0) ++r;
          return r;
        }
        function bnGetLowestSetBit() {
          for (var i = 0; i < this.t; ++i)
            if (this[i] != 0) return i * this.DB + lbit(this[i]);
          if (this.s < 0) return this.t * this.DB;
          return -1;
        }
        function cbit(x) {
          var r = 0;
          while (x != 0) {
            x &= x - 1;
            ++r;
          }
          return r;
        }
        function bnBitCount() {
          var r = 0, x = this.s & this.DM;
          for (var i = 0; i < this.t; ++i) r += cbit(this[i] ^ x);
          return r;
        }
        function bnTestBit(n) {
          var j = Math.floor(n / this.DB);
          if (j >= this.t) return this.s != 0;
          return (this[j] & 1 << n % this.DB) != 0;
        }
        function bnpChangeBit(n, op) {
          var r = BigInteger.ONE.shiftLeft(n);
          this.bitwiseTo(r, op, r);
          return r;
        }
        function bnSetBit(n) {
          return this.changeBit(n, op_or);
        }
        function bnClearBit(n) {
          return this.changeBit(n, op_andnot);
        }
        function bnFlipBit(n) {
          return this.changeBit(n, op_xor);
        }
        function bnpAddTo(a, r) {
          var i = 0, c = 0, m = Math.min(a.t, this.t);
          while (i < m) {
            c += this[i] + a[i];
            r[i++] = c & this.DM;
            c >>= this.DB;
          }
          if (a.t < this.t) {
            c += a.s;
            while (i < this.t) {
              c += this[i];
              r[i++] = c & this.DM;
              c >>= this.DB;
            }
            c += this.s;
          } else {
            c += this.s;
            while (i < a.t) {
              c += a[i];
              r[i++] = c & this.DM;
              c >>= this.DB;
            }
            c += a.s;
          }
          r.s = c < 0 ? -1 : 0;
          if (c > 0) r[i++] = c;
          else if (c < -1) r[i++] = this.DV + c;
          r.t = i;
          r.clamp();
        }
        function bnAdd(a) {
          var r = nbi();
          this.addTo(a, r);
          return r;
        }
        function bnSubtract(a) {
          var r = nbi();
          this.subTo(a, r);
          return r;
        }
        function bnMultiply(a) {
          var r = nbi();
          this.multiplyTo(a, r);
          return r;
        }
        function bnSquare() {
          var r = nbi();
          this.squareTo(r);
          return r;
        }
        function bnDivide(a) {
          var r = nbi();
          this.divRemTo(a, r, null);
          return r;
        }
        function bnRemainder(a) {
          var r = nbi();
          this.divRemTo(a, null, r);
          return r;
        }
        function bnDivideAndRemainder(a) {
          var q = nbi(), r = nbi();
          this.divRemTo(a, q, r);
          return new Array(q, r);
        }
        function bnpDMultiply(n) {
          this[this.t] = this.am(0, n - 1, this, 0, 0, this.t);
          ++this.t;
          this.clamp();
        }
        function bnpDAddOffset(n, w) {
          if (n == 0) return;
          while (this.t <= w) this[this.t++] = 0;
          this[w] += n;
          while (this[w] >= this.DV) {
            this[w] -= this.DV;
            if (++w >= this.t) this[this.t++] = 0;
            ++this[w];
          }
        }
        function NullExp() {
        }
        function nNop(x) {
          return x;
        }
        function nMulTo(x, y, r) {
          x.multiplyTo(y, r);
        }
        function nSqrTo(x, r) {
          x.squareTo(r);
        }
        NullExp.prototype.convert = nNop;
        NullExp.prototype.revert = nNop;
        NullExp.prototype.mulTo = nMulTo;
        NullExp.prototype.sqrTo = nSqrTo;
        function bnPow(e) {
          return this.exp(e, new NullExp());
        }
        function bnpMultiplyLowerTo(a, n, r) {
          var i = Math.min(this.t + a.t, n);
          r.s = 0;
          r.t = i;
          while (i > 0) r[--i] = 0;
          var j;
          for (j = r.t - this.t; i < j; ++i) r[i + this.t] = this.am(0, a[i], r, i, 0, this.t);
          for (j = Math.min(a.t, n); i < j; ++i) this.am(0, a[i], r, i, 0, n - i);
          r.clamp();
        }
        function bnpMultiplyUpperTo(a, n, r) {
          --n;
          var i = r.t = this.t + a.t - n;
          r.s = 0;
          while (--i >= 0) r[i] = 0;
          for (i = Math.max(n - this.t, 0); i < a.t; ++i)
            r[this.t + i - n] = this.am(n - i, a[i], r, 0, 0, this.t + i - n);
          r.clamp();
          r.drShiftTo(1, r);
        }
        function Barrett(m) {
          this.r2 = nbi();
          this.q3 = nbi();
          BigInteger.ONE.dlShiftTo(2 * m.t, this.r2);
          this.mu = this.r2.divide(m);
          this.m = m;
        }
        function barrettConvert(x) {
          if (x.s < 0 || x.t > 2 * this.m.t) return x.mod(this.m);
          else if (x.compareTo(this.m) < 0) return x;
          else {
            var r = nbi();
            x.copyTo(r);
            this.reduce(r);
            return r;
          }
        }
        function barrettRevert(x) {
          return x;
        }
        function barrettReduce(x) {
          x.drShiftTo(this.m.t - 1, this.r2);
          if (x.t > this.m.t + 1) {
            x.t = this.m.t + 1;
            x.clamp();
          }
          this.mu.multiplyUpperTo(this.r2, this.m.t + 1, this.q3);
          this.m.multiplyLowerTo(this.q3, this.m.t + 1, this.r2);
          while (x.compareTo(this.r2) < 0) x.dAddOffset(1, this.m.t + 1);
          x.subTo(this.r2, x);
          while (x.compareTo(this.m) >= 0) x.subTo(this.m, x);
        }
        function barrettSqrTo(x, r) {
          x.squareTo(r);
          this.reduce(r);
        }
        function barrettMulTo(x, y, r) {
          x.multiplyTo(y, r);
          this.reduce(r);
        }
        Barrett.prototype.convert = barrettConvert;
        Barrett.prototype.revert = barrettRevert;
        Barrett.prototype.reduce = barrettReduce;
        Barrett.prototype.mulTo = barrettMulTo;
        Barrett.prototype.sqrTo = barrettSqrTo;
        function bnModPow(e, m) {
          var i = e.bitLength(), k, r = nbv(1), z2;
          if (i <= 0) return r;
          else if (i < 18) k = 1;
          else if (i < 48) k = 3;
          else if (i < 144) k = 4;
          else if (i < 768) k = 5;
          else k = 6;
          if (i < 8)
            z2 = new Classic(m);
          else if (m.isEven())
            z2 = new Barrett(m);
          else
            z2 = new Montgomery(m);
          var g = new Array(), n = 3, k1 = k - 1, km = (1 << k) - 1;
          g[1] = z2.convert(this);
          if (k > 1) {
            var g2 = nbi();
            z2.sqrTo(g[1], g2);
            while (n <= km) {
              g[n] = nbi();
              z2.mulTo(g2, g[n - 2], g[n]);
              n += 2;
            }
          }
          var j = e.t - 1, w, is1 = true, r2 = nbi(), t2;
          i = nbits(e[j]) - 1;
          while (j >= 0) {
            if (i >= k1) w = e[j] >> i - k1 & km;
            else {
              w = (e[j] & (1 << i + 1) - 1) << k1 - i;
              if (j > 0) w |= e[j - 1] >> this.DB + i - k1;
            }
            n = k;
            while ((w & 1) == 0) {
              w >>= 1;
              --n;
            }
            if ((i -= n) < 0) {
              i += this.DB;
              --j;
            }
            if (is1) {
              g[w].copyTo(r);
              is1 = false;
            } else {
              while (n > 1) {
                z2.sqrTo(r, r2);
                z2.sqrTo(r2, r);
                n -= 2;
              }
              if (n > 0) z2.sqrTo(r, r2);
              else {
                t2 = r;
                r = r2;
                r2 = t2;
              }
              z2.mulTo(r2, g[w], r);
            }
            while (j >= 0 && (e[j] & 1 << i) == 0) {
              z2.sqrTo(r, r2);
              t2 = r;
              r = r2;
              r2 = t2;
              if (--i < 0) {
                i = this.DB - 1;
                --j;
              }
            }
          }
          return z2.revert(r);
        }
        function bnGCD(a) {
          var x = this.s < 0 ? this.negate() : this.clone();
          var y = a.s < 0 ? a.negate() : a.clone();
          if (x.compareTo(y) < 0) {
            var t2 = x;
            x = y;
            y = t2;
          }
          var i = x.getLowestSetBit(), g = y.getLowestSetBit();
          if (g < 0) return x;
          if (i < g) g = i;
          if (g > 0) {
            x.rShiftTo(g, x);
            y.rShiftTo(g, y);
          }
          while (x.signum() > 0) {
            if ((i = x.getLowestSetBit()) > 0) x.rShiftTo(i, x);
            if ((i = y.getLowestSetBit()) > 0) y.rShiftTo(i, y);
            if (x.compareTo(y) >= 0) {
              x.subTo(y, x);
              x.rShiftTo(1, x);
            } else {
              y.subTo(x, y);
              y.rShiftTo(1, y);
            }
          }
          if (g > 0) y.lShiftTo(g, y);
          return y;
        }
        function bnpModInt(n) {
          if (n <= 0) return 0;
          var d = this.DV % n, r = this.s < 0 ? n - 1 : 0;
          if (this.t > 0)
            if (d == 0) r = this[0] % n;
            else for (var i = this.t - 1; i >= 0; --i) r = (d * r + this[i]) % n;
          return r;
        }
        function bnModInverse(m) {
          var ac = m.isEven();
          if (this.isEven() && ac || m.signum() == 0) return BigInteger.ZERO;
          var u = m.clone(), v = this.clone();
          var a = nbv(1), b = nbv(0), c = nbv(0), d = nbv(1);
          while (u.signum() != 0) {
            while (u.isEven()) {
              u.rShiftTo(1, u);
              if (ac) {
                if (!a.isEven() || !b.isEven()) {
                  a.addTo(this, a);
                  b.subTo(m, b);
                }
                a.rShiftTo(1, a);
              } else if (!b.isEven()) b.subTo(m, b);
              b.rShiftTo(1, b);
            }
            while (v.isEven()) {
              v.rShiftTo(1, v);
              if (ac) {
                if (!c.isEven() || !d.isEven()) {
                  c.addTo(this, c);
                  d.subTo(m, d);
                }
                c.rShiftTo(1, c);
              } else if (!d.isEven()) d.subTo(m, d);
              d.rShiftTo(1, d);
            }
            if (u.compareTo(v) >= 0) {
              u.subTo(v, u);
              if (ac) a.subTo(c, a);
              b.subTo(d, b);
            } else {
              v.subTo(u, v);
              if (ac) c.subTo(a, c);
              d.subTo(b, d);
            }
          }
          if (v.compareTo(BigInteger.ONE) != 0) return BigInteger.ZERO;
          if (d.compareTo(m) >= 0) return d.subtract(m);
          if (d.signum() < 0) d.addTo(m, d);
          else return d;
          if (d.signum() < 0) return d.add(m);
          else return d;
        }
        var lowprimes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113, 127, 131, 137, 139, 149, 151, 157, 163, 167, 173, 179, 181, 191, 193, 197, 199, 211, 223, 227, 229, 233, 239, 241, 251, 257, 263, 269, 271, 277, 281, 283, 293, 307, 311, 313, 317, 331, 337, 347, 349, 353, 359, 367, 373, 379, 383, 389, 397, 401, 409, 419, 421, 431, 433, 439, 443, 449, 457, 461, 463, 467, 479, 487, 491, 499, 503, 509, 521, 523, 541, 547, 557, 563, 569, 571, 577, 587, 593, 599, 601, 607, 613, 617, 619, 631, 641, 643, 647, 653, 659, 661, 673, 677, 683, 691, 701, 709, 719, 727, 733, 739, 743, 751, 757, 761, 769, 773, 787, 797, 809, 811, 821, 823, 827, 829, 839, 853, 857, 859, 863, 877, 881, 883, 887, 907, 911, 919, 929, 937, 941, 947, 953, 967, 971, 977, 983, 991, 997];
        var lplim = (1 << 26) / lowprimes[lowprimes.length - 1];
        function bnIsProbablePrime(t2) {
          var i, x = this.abs();
          if (x.t == 1 && x[0] <= lowprimes[lowprimes.length - 1]) {
            for (i = 0; i < lowprimes.length; ++i)
              if (x[0] == lowprimes[i]) return true;
            return false;
          }
          if (x.isEven()) return false;
          i = 1;
          while (i < lowprimes.length) {
            var m = lowprimes[i], j = i + 1;
            while (j < lowprimes.length && m < lplim) m *= lowprimes[j++];
            m = x.modInt(m);
            while (i < j) if (m % lowprimes[i++] == 0) return false;
          }
          return x.millerRabin(t2);
        }
        function bnpMillerRabin(t2) {
          var n1 = this.subtract(BigInteger.ONE);
          var k = n1.getLowestSetBit();
          if (k <= 0) return false;
          var r = n1.shiftRight(k);
          t2 = t2 + 1 >> 1;
          if (t2 > lowprimes.length) t2 = lowprimes.length;
          var a = nbi();
          for (var i = 0; i < t2; ++i) {
            a.fromInt(lowprimes[Math.floor(Math.random() * lowprimes.length)]);
            var y = a.modPow(r, this);
            if (y.compareTo(BigInteger.ONE) != 0 && y.compareTo(n1) != 0) {
              var j = 1;
              while (j++ < k && y.compareTo(n1) != 0) {
                y = y.modPowInt(2, this);
                if (y.compareTo(BigInteger.ONE) == 0) return false;
              }
              if (y.compareTo(n1) != 0) return false;
            }
          }
          return true;
        }
        BigInteger.prototype.chunkSize = bnpChunkSize;
        BigInteger.prototype.toRadix = bnpToRadix;
        BigInteger.prototype.fromRadix = bnpFromRadix;
        BigInteger.prototype.fromNumber = bnpFromNumber;
        BigInteger.prototype.bitwiseTo = bnpBitwiseTo;
        BigInteger.prototype.changeBit = bnpChangeBit;
        BigInteger.prototype.addTo = bnpAddTo;
        BigInteger.prototype.dMultiply = bnpDMultiply;
        BigInteger.prototype.dAddOffset = bnpDAddOffset;
        BigInteger.prototype.multiplyLowerTo = bnpMultiplyLowerTo;
        BigInteger.prototype.multiplyUpperTo = bnpMultiplyUpperTo;
        BigInteger.prototype.modInt = bnpModInt;
        BigInteger.prototype.millerRabin = bnpMillerRabin;
        BigInteger.prototype.clone = bnClone;
        BigInteger.prototype.intValue = bnIntValue;
        BigInteger.prototype.byteValue = bnByteValue;
        BigInteger.prototype.shortValue = bnShortValue;
        BigInteger.prototype.signum = bnSigNum;
        BigInteger.prototype.toByteArray = bnToByteArray;
        BigInteger.prototype.equals = bnEquals;
        BigInteger.prototype.min = bnMin;
        BigInteger.prototype.max = bnMax;
        BigInteger.prototype.and = bnAnd;
        BigInteger.prototype.or = bnOr;
        BigInteger.prototype.xor = bnXor;
        BigInteger.prototype.andNot = bnAndNot;
        BigInteger.prototype.not = bnNot;
        BigInteger.prototype.shiftLeft = bnShiftLeft;
        BigInteger.prototype.shiftRight = bnShiftRight;
        BigInteger.prototype.getLowestSetBit = bnGetLowestSetBit;
        BigInteger.prototype.bitCount = bnBitCount;
        BigInteger.prototype.testBit = bnTestBit;
        BigInteger.prototype.setBit = bnSetBit;
        BigInteger.prototype.clearBit = bnClearBit;
        BigInteger.prototype.flipBit = bnFlipBit;
        BigInteger.prototype.add = bnAdd;
        BigInteger.prototype.subtract = bnSubtract;
        BigInteger.prototype.multiply = bnMultiply;
        BigInteger.prototype.divide = bnDivide;
        BigInteger.prototype.remainder = bnRemainder;
        BigInteger.prototype.divideAndRemainder = bnDivideAndRemainder;
        BigInteger.prototype.modPow = bnModPow;
        BigInteger.prototype.modInverse = bnModInverse;
        BigInteger.prototype.pow = bnPow;
        BigInteger.prototype.gcd = bnGCD;
        BigInteger.prototype.isProbablePrime = bnIsProbablePrime;
        BigInteger.prototype.square = bnSquare;
        BigInteger.prototype.Barrett = Barrett;
        var rng_state;
        var rng_pool;
        var rng_pptr;
        function rng_seed_int(x) {
          rng_pool[rng_pptr++] ^= x & 255;
          rng_pool[rng_pptr++] ^= x >> 8 & 255;
          rng_pool[rng_pptr++] ^= x >> 16 & 255;
          rng_pool[rng_pptr++] ^= x >> 24 & 255;
          if (rng_pptr >= rng_psize) rng_pptr -= rng_psize;
        }
        function rng_seed_time() {
          rng_seed_int((/* @__PURE__ */ new Date()).getTime());
        }
        if (rng_pool == null) {
          rng_pool = new Array();
          rng_pptr = 0;
          var t;
          if (typeof window !== "undefined" && window.crypto) {
            if (window.crypto.getRandomValues) {
              var ua = new Uint8Array(32);
              window.crypto.getRandomValues(ua);
              for (t = 0; t < 32; ++t)
                rng_pool[rng_pptr++] = ua[t];
            } else if (navigator.appName == "Netscape" && navigator.appVersion < "5") {
              var z = window.crypto.random(32);
              for (t = 0; t < z.length; ++t)
                rng_pool[rng_pptr++] = z.charCodeAt(t) & 255;
            }
          }
          while (rng_pptr < rng_psize) {
            t = Math.floor(65536 * Math.random());
            rng_pool[rng_pptr++] = t >>> 8;
            rng_pool[rng_pptr++] = t & 255;
          }
          rng_pptr = 0;
          rng_seed_time();
        }
        function rng_get_byte() {
          if (rng_state == null) {
            rng_seed_time();
            rng_state = prng_newstate();
            rng_state.init(rng_pool);
            for (rng_pptr = 0; rng_pptr < rng_pool.length; ++rng_pptr)
              rng_pool[rng_pptr] = 0;
            rng_pptr = 0;
          }
          return rng_state.next();
        }
        function rng_get_bytes(ba) {
          var i;
          for (i = 0; i < ba.length; ++i) ba[i] = rng_get_byte();
        }
        function SecureRandom() {
        }
        SecureRandom.prototype.nextBytes = rng_get_bytes;
        function Arcfour() {
          this.i = 0;
          this.j = 0;
          this.S = new Array();
        }
        function ARC4init(key) {
          var i, j, t2;
          for (i = 0; i < 256; ++i)
            this.S[i] = i;
          j = 0;
          for (i = 0; i < 256; ++i) {
            j = j + this.S[i] + key[i % key.length] & 255;
            t2 = this.S[i];
            this.S[i] = this.S[j];
            this.S[j] = t2;
          }
          this.i = 0;
          this.j = 0;
        }
        function ARC4next() {
          var t2;
          this.i = this.i + 1 & 255;
          this.j = this.j + this.S[this.i] & 255;
          t2 = this.S[this.i];
          this.S[this.i] = this.S[this.j];
          this.S[this.j] = t2;
          return this.S[t2 + this.S[this.i] & 255];
        }
        Arcfour.prototype.init = ARC4init;
        Arcfour.prototype.next = ARC4next;
        function prng_newstate() {
          return new Arcfour();
        }
        var rng_psize = 256;
        if (typeof exports !== "undefined") {
          exports = module.exports = {
            default: BigInteger,
            BigInteger,
            SecureRandom
          };
        } else {
          this.jsbn = {
            BigInteger,
            SecureRandom
          };
        }
      }).call(exports);
    }
  });

  // node_modules/sm-crypto/src/sm2/asn1.js
  var require_asn1 = __commonJS({
    "node_modules/sm-crypto/src/sm2/asn1.js"(exports, module) {
      var { BigInteger } = require_jsbn();
      function bigintToValue(bigint) {
        let h = bigint.toString(16);
        if (h[0] !== "-") {
          if (h.length % 2 === 1) h = "0" + h;
          else if (!h.match(/^[0-7]/)) h = "00" + h;
        } else {
          h = h.substr(1);
          let len = h.length;
          if (len % 2 === 1) len += 1;
          else if (!h.match(/^[0-7]/)) len += 2;
          let mask = "";
          for (let i = 0; i < len; i++) mask += "f";
          mask = new BigInteger(mask, 16);
          h = mask.xor(bigint).add(BigInteger.ONE);
          h = h.toString(16).replace(/^-/, "");
        }
        return h;
      }
      var ASN1Object = class {
        constructor() {
          this.tlv = null;
          this.t = "00";
          this.l = "00";
          this.v = "";
        }
        /**
         * 获取 der 编码比特流16进制串
         */
        getEncodedHex() {
          if (!this.tlv) {
            this.v = this.getValue();
            this.l = this.getLength();
            this.tlv = this.t + this.l + this.v;
          }
          return this.tlv;
        }
        getLength() {
          const n = this.v.length / 2;
          let nHex = n.toString(16);
          if (nHex.length % 2 === 1) nHex = "0" + nHex;
          if (n < 128) {
            return nHex;
          } else {
            const head = 128 + nHex.length / 2;
            return head.toString(16) + nHex;
          }
        }
        getValue() {
          return "";
        }
      };
      var DERInteger = class extends ASN1Object {
        constructor(bigint) {
          super();
          this.t = "02";
          if (bigint) this.v = bigintToValue(bigint);
        }
        getValue() {
          return this.v;
        }
      };
      var DERSequence = class extends ASN1Object {
        constructor(asn1Array) {
          super();
          this.t = "30";
          this.asn1Array = asn1Array;
        }
        getValue() {
          this.v = this.asn1Array.map((asn1Object) => asn1Object.getEncodedHex()).join("");
          return this.v;
        }
      };
      function parseLength(str, start) {
        if (start + 2 > str.length) throw new Error("invalid DER: length field truncated");
        const first = parseInt(str.substring(start, start + 2), 16);
        if (first < 128) {
          return { len: first, lenOfL: 1 };
        }
        const numBytes = first & 127;
        if (numBytes === 0) throw new Error("invalid DER: indefinite length not allowed");
        if (numBytes > 4) throw new Error("invalid DER: length too large");
        if (start + 2 + numBytes * 2 > str.length) throw new Error("invalid DER: length field truncated");
        const lenHex = str.substring(start + 2, start + 2 + numBytes * 2);
        const len = parseInt(lenHex, 16);
        if (len < 128) throw new Error("invalid DER: length not minimally encoded (should use short form)");
        if (lenHex.substring(0, 2) === "00") throw new Error("invalid DER: length has leading zero byte");
        return { len, lenOfL: 1 + numBytes };
      }
      function parseTLV(str, start) {
        if (start + 2 > str.length) throw new Error("invalid DER: tag field truncated");
        const tag = str.substring(start, start + 2);
        const { len, lenOfL } = parseLength(str, start + 2);
        const valueStart = start + 2 + lenOfL * 2;
        const valueEnd = valueStart + len * 2;
        if (valueEnd > str.length) throw new Error("invalid DER: value truncated");
        return {
          tag,
          valueHex: str.substring(valueStart, valueEnd),
          nextStart: valueEnd
        };
      }
      function assertMinimalInteger(valueHex) {
        if (valueHex.length === 0) throw new Error("invalid DER: INTEGER is empty");
        const firstByte = parseInt(valueHex.substring(0, 2), 16);
        if (firstByte & 128) throw new Error("invalid DER: INTEGER is negative");
        if (firstByte === 0) {
          if (valueHex.length === 2) {
            return;
          }
          const secondByte = parseInt(valueHex.substring(2, 4), 16);
          if (!(secondByte & 128)) throw new Error("invalid DER: INTEGER has non-minimal leading zero");
        }
      }
      module.exports = {
        /**
         * ASN.1 der 编码，针对 sm2 签名
         */
        encodeDer(r, s) {
          const derR = new DERInteger(r);
          const derS = new DERInteger(s);
          const derSeq = new DERSequence([derR, derS]);
          return derSeq.getEncodedHex();
        },
        /**
         * 解析 ASN.1 der，针对 sm2 验签
         * 严格校验规范 DER 编码，拒绝任何非规范编码（例如：
         * INTEGER 前导 00 填充、外层 SEQUENCE 长度与实际不符、错误的 tag 等），
         * 以避免签名可延展性（signature malleability）问题。
         */
        decodeDer(input) {
          if (typeof input !== "string" || input.length % 2 !== 0 || !/^[0-9a-fA-F]+$/.test(input)) {
            throw new Error("invalid DER: input must be a hex string of even length");
          }
          if (input.substring(0, 2) !== "30") throw new Error("invalid DER: expected SEQUENCE (0x30)");
          const seqLenInfo = parseLength(input, 2);
          const seqValueOffset = 2 + seqLenInfo.lenOfL * 2;
          if (seqValueOffset + seqLenInfo.len * 2 !== input.length) {
            throw new Error("invalid DER: SEQUENCE length does not match input length");
          }
          const rParsed = parseTLV(input, seqValueOffset);
          if (rParsed.tag !== "02") throw new Error("invalid DER: expected INTEGER (0x02) for R");
          assertMinimalInteger(rParsed.valueHex);
          const sParsed = parseTLV(input, rParsed.nextStart);
          if (sParsed.tag !== "02") throw new Error("invalid DER: expected INTEGER (0x02) for S");
          assertMinimalInteger(sParsed.valueHex);
          if (sParsed.nextStart !== input.length) throw new Error("invalid DER: trailing bytes inside SEQUENCE");
          const r = new BigInteger(rParsed.valueHex, 16);
          const s = new BigInteger(sParsed.valueHex, 16);
          return { r, s };
        }
      };
    }
  });

  // node_modules/sm-crypto/src/sm2/ec.js
  var require_ec = __commonJS({
    "node_modules/sm-crypto/src/sm2/ec.js"(exports, module) {
      var { BigInteger } = require_jsbn();
      var TWO = new BigInteger("2");
      var THREE = new BigInteger("3");
      var ECFieldElementFp = class _ECFieldElementFp {
        constructor(q, x) {
          this.x = x;
          this.q = q;
        }
        /**
         * 判断相等
         */
        equals(other) {
          if (other === this) return true;
          return this.q.equals(other.q) && this.x.equals(other.x);
        }
        /**
         * 返回具体数值
         */
        toBigInteger() {
          return this.x;
        }
        /**
         * 取反
         */
        negate() {
          return new _ECFieldElementFp(this.q, this.x.negate().mod(this.q));
        }
        /**
         * 相加
         */
        add(b) {
          return new _ECFieldElementFp(this.q, this.x.add(b.toBigInteger()).mod(this.q));
        }
        /**
         * 相减
         */
        subtract(b) {
          return new _ECFieldElementFp(this.q, this.x.subtract(b.toBigInteger()).mod(this.q));
        }
        /**
         * 相乘
         */
        multiply(b) {
          return new _ECFieldElementFp(this.q, this.x.multiply(b.toBigInteger()).mod(this.q));
        }
        /**
         * 相除
         */
        divide(b) {
          return new _ECFieldElementFp(this.q, this.x.multiply(b.toBigInteger().modInverse(this.q)).mod(this.q));
        }
        /**
         * 平方
         */
        square() {
          return new _ECFieldElementFp(this.q, this.x.square().mod(this.q));
        }
      };
      var ECPointFp = class _ECPointFp {
        constructor(curve, x, y, z) {
          this.curve = curve;
          this.x = x;
          this.y = y;
          this.z = z == null ? BigInteger.ONE : z;
          this.zinv = null;
        }
        getX() {
          if (this.zinv === null) this.zinv = this.z.modInverse(this.curve.q);
          return this.curve.fromBigInteger(this.x.toBigInteger().multiply(this.zinv).mod(this.curve.q));
        }
        getY() {
          if (this.zinv === null) this.zinv = this.z.modInverse(this.curve.q);
          return this.curve.fromBigInteger(this.y.toBigInteger().multiply(this.zinv).mod(this.curve.q));
        }
        /**
         * 判断相等
         */
        equals(other) {
          if (other === this) return true;
          if (this.isInfinity()) return other.isInfinity();
          if (other.isInfinity()) return this.isInfinity();
          const u = other.y.toBigInteger().multiply(this.z).subtract(this.y.toBigInteger().multiply(other.z)).mod(this.curve.q);
          if (!u.equals(BigInteger.ZERO)) return false;
          const v = other.x.toBigInteger().multiply(this.z).subtract(this.x.toBigInteger().multiply(other.z)).mod(this.curve.q);
          return v.equals(BigInteger.ZERO);
        }
        /**
         * 是否是无穷远点
         */
        isInfinity() {
          if (this.x === null && this.y === null) return true;
          return this.z.equals(BigInteger.ZERO) && !this.y.toBigInteger().equals(BigInteger.ZERO);
        }
        /**
         * 取反，x 轴对称点
         */
        negate() {
          return new _ECPointFp(this.curve, this.x, this.y.negate(), this.z);
        }
        /**
         * 相加
         *
         * 标准射影坐标系：
         *
         * λ1 = x1 * z2
         * λ2 = x2 * z1
         * λ3 = λ1 − λ2
         * λ4 = y1 * z2
         * λ5 = y2 * z1
         * λ6 = λ4 − λ5
         * λ7 = λ1 + λ2
         * λ8 = z1 * z2
         * λ9 = λ3^2
         * λ10 = λ3 * λ9
         * λ11 = λ8 * λ6^2 − λ7 * λ9
         * x3 = λ3 * λ11
         * y3 = λ6 * (λ9 * λ1 − λ11) − λ4 * λ10
         * z3 = λ10 * λ8
         */
        add(b) {
          if (this.isInfinity()) return b;
          if (b.isInfinity()) return this;
          const x1 = this.x.toBigInteger();
          const y1 = this.y.toBigInteger();
          const z1 = this.z;
          const x2 = b.x.toBigInteger();
          const y2 = b.y.toBigInteger();
          const z2 = b.z;
          const q = this.curve.q;
          const w1 = x1.multiply(z2).mod(q);
          const w2 = x2.multiply(z1).mod(q);
          const w3 = w1.subtract(w2);
          const w4 = y1.multiply(z2).mod(q);
          const w5 = y2.multiply(z1).mod(q);
          const w6 = w4.subtract(w5);
          if (BigInteger.ZERO.equals(w3)) {
            if (BigInteger.ZERO.equals(w6)) {
              return this.twice();
            }
            return this.curve.infinity;
          }
          const w7 = w1.add(w2);
          const w8 = z1.multiply(z2).mod(q);
          const w9 = w3.square().mod(q);
          const w10 = w3.multiply(w9).mod(q);
          const w11 = w8.multiply(w6.square()).subtract(w7.multiply(w9)).mod(q);
          const x3 = w3.multiply(w11).mod(q);
          const y3 = w6.multiply(w9.multiply(w1).subtract(w11)).subtract(w4.multiply(w10)).mod(q);
          const z3 = w10.multiply(w8).mod(q);
          return new _ECPointFp(this.curve, this.curve.fromBigInteger(x3), this.curve.fromBigInteger(y3), z3);
        }
        /**
         * 自加
         *
         * 标准射影坐标系：
         *
         * λ1 = 3 * x1^2 + a * z1^2
         * λ2 = 2 * y1 * z1
         * λ3 = y1^2
         * λ4 = λ3 * x1 * z1
         * λ5 = λ2^2
         * λ6 = λ1^2 − 8 * λ4
         * x3 = λ2 * λ6
         * y3 = λ1 * (4 * λ4 − λ6) − 2 * λ5 * λ3
         * z3 = λ2 * λ5
         */
        twice() {
          if (this.isInfinity()) return this;
          if (!this.y.toBigInteger().signum()) return this.curve.infinity;
          const x1 = this.x.toBigInteger();
          const y1 = this.y.toBigInteger();
          const z1 = this.z;
          const q = this.curve.q;
          const a = this.curve.a.toBigInteger();
          const w1 = x1.square().multiply(THREE).add(a.multiply(z1.square())).mod(q);
          const w2 = y1.shiftLeft(1).multiply(z1).mod(q);
          const w3 = y1.square().mod(q);
          const w4 = w3.multiply(x1).multiply(z1).mod(q);
          const w5 = w2.square().mod(q);
          const w6 = w1.square().subtract(w4.shiftLeft(3)).mod(q);
          const x3 = w2.multiply(w6).mod(q);
          const y3 = w1.multiply(w4.shiftLeft(2).subtract(w6)).subtract(w5.shiftLeft(1).multiply(w3)).mod(q);
          const z3 = w2.multiply(w5).mod(q);
          return new _ECPointFp(this.curve, this.curve.fromBigInteger(x3), this.curve.fromBigInteger(y3), z3);
        }
        /**
         * 倍点计算
         */
        multiply(k) {
          if (this.isInfinity()) return this;
          if (!k.signum()) return this.curve.infinity;
          const k3 = k.multiply(THREE);
          const neg = this.negate();
          let Q = this;
          for (let i = k3.bitLength() - 2; i > 0; i--) {
            Q = Q.twice();
            const k3Bit = k3.testBit(i);
            const kBit = k.testBit(i);
            if (k3Bit !== kBit) {
              Q = Q.add(k3Bit ? this : neg);
            }
          }
          return Q;
        }
      };
      var ECCurveFp = class {
        constructor(q, a, b) {
          this.q = q;
          this.a = this.fromBigInteger(a);
          this.b = this.fromBigInteger(b);
          this.infinity = new ECPointFp(this, null, null);
        }
        /**
         * 判断两个椭圆曲线是否相等
         */
        equals(other) {
          if (other === this) return true;
          return this.q.equals(other.q) && this.a.equals(other.a) && this.b.equals(other.b);
        }
        /**
         * 生成椭圆曲线域元素
         */
        fromBigInteger(x) {
          return new ECFieldElementFp(this.q, x);
        }
        /**
         * 解析 16 进制串为椭圆曲线点
         */
        decodePointHex(s) {
          if (typeof s !== "string" || s.length < 2 || s.length % 2 !== 0 || !/^[0-9a-fA-F]+$/.test(s)) return null;
          switch (parseInt(s.substr(0, 2), 16)) {
            // 第一个字节
            case 0:
              if (s.length !== 2) return null;
              return this.infinity;
            case 2:
            case 3:
              if (s.length !== 2 + 64) return null;
              const x = this.fromBigInteger(new BigInteger(s.substr(2), 16));
              let y = this.fromBigInteger(x.multiply(x.square()).add(
                x.multiply(this.a)
              ).add(this.b).toBigInteger().modPow(
                this.q.divide(new BigInteger("4")).add(BigInteger.ONE),
                this.q
              ));
              if (!y.toBigInteger().mod(TWO).equals(new BigInteger(s.substr(0, 2), 16).subtract(TWO))) {
                y = y.negate();
              }
              return new ECPointFp(this, x, y);
            case 4:
            case 6:
            case 7:
              if (s.length !== 2 + 128) return null;
              const len = (s.length - 2) / 2;
              const xHex = s.substr(2, len);
              const yHex = s.substr(len + 2, len);
              return new ECPointFp(this, this.fromBigInteger(new BigInteger(xHex, 16)), this.fromBigInteger(new BigInteger(yHex, 16)));
            default:
              return null;
          }
        }
      };
      module.exports = {
        ECPointFp,
        ECCurveFp
      };
    }
  });

  // node_modules/sm-crypto/src/sm2/rng.js
  var require_rng = __commonJS({
    "node_modules/sm-crypto/src/sm2/rng.js"(exports, module) {
      var rngState;
      var rngPool;
      var rngPptr;
      var rngPsize = 256;
      var Arcfour = class {
        constructor() {
          this.i = 0;
          this.j = 0;
          this.S = [];
        }
        // Initialize arcfour context from key, an array of ints, each from [0..255]
        init(key) {
          let i;
          let j;
          let t;
          for (i = 0; i < 256; ++i) this.S[i] = i;
          j = 0;
          for (i = 0; i < 256; ++i) {
            j = j + this.S[i] + key[i % key.length] & 255;
            t = this.S[i];
            this.S[i] = this.S[j];
            this.S[j] = t;
          }
          this.i = 0;
          this.j = 0;
        }
        next() {
          this.i = this.i + 1 & 255;
          this.j = this.j + this.S[this.i] & 255;
          const t = this.S[this.i];
          this.S[this.i] = this.S[this.j];
          this.S[this.j] = t;
          return this.S[t + this.S[this.i] & 255];
        }
      };
      function rngSeedInt(x) {
        rngPool[rngPptr++] ^= x & 255;
        rngPool[rngPptr++] ^= x >> 8 & 255;
        rngPool[rngPptr++] ^= x >> 16 & 255;
        rngPool[rngPptr++] ^= x >> 24 & 255;
        if (rngPptr >= rngPsize) rngPptr -= rngPsize;
      }
      function rngSeedTime() {
        rngSeedInt((/* @__PURE__ */ new Date()).getTime());
      }
      if (rngPool == null) {
        rngPool = [];
        rngPptr = 0;
        let t;
        const ua = new Uint8Array(32);
        if (typeof window !== "undefined" && window.crypto && window.crypto.getRandomValues) {
          window.crypto.getRandomValues(ua);
          for (t = 0; t < 32; ++t) rngPool[rngPptr++] = ua[t];
        } else {
          const nodeRequire = typeof module !== "undefined" && typeof module.require === "function" ? module.require.bind(module) : null;
          const nodeCrypto = nodeRequire ? nodeRequire("crypto") : null;
          if (nodeCrypto) nodeCrypto.getRandomValues(ua);
          else if (globalThis.crypto) globalThis.crypto.getRandomValues(ua);
          else throw new Error("\u5F53\u524D\u73AF\u5883\u4E0D\u652F\u6301 crypto.getRandomValues\uFF01");
          for (t = 0; t < 32; ++t) rngPool[rngPptr++] = ua[t];
        }
        rngPptr = 0;
        rngSeedTime();
      }
      function rngGetByte() {
        if (rngState == null) {
          rngSeedTime();
          rngState = new Arcfour();
          rngState.init(rngPool);
          for (rngPptr = 0; rngPptr < rngPool.length; ++rngPptr) rngPool[rngPptr] = 0;
          rngPptr = 0;
        }
        return rngState.next();
      }
      var SecureRandom = class {
        // eslint-disable-next-line class-methods-use-this
        nextBytes(ba) {
          for (let i = 0; i < ba.length; ++i) ba[i] = rngGetByte();
        }
      };
      module.exports = {
        SecureRandom
      };
    }
  });

  // node_modules/sm-crypto/src/sm2/utils.js
  var require_utils = __commonJS({
    "node_modules/sm-crypto/src/sm2/utils.js"(exports, module) {
      var { BigInteger } = require_jsbn();
      var { ECCurveFp } = require_ec();
      var { SecureRandom } = require_rng();
      var rng = new SecureRandom();
      var { curve, G, n } = generateEcparam();
      function getGlobalCurve() {
        return curve;
      }
      function generateEcparam() {
        const p = new BigInteger("FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFF", 16);
        const a = new BigInteger("FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFC", 16);
        const b = new BigInteger("28E9FA9E9D9F5E344D5A9E4BCF6509A7F39789F515AB8F92DDBCBD414D940E93", 16);
        const curve2 = new ECCurveFp(p, a, b);
        const gxHex = "32C4AE2C1F1981195F9904466A39C9948FE30BBFF2660BE1715A4589334C74C7";
        const gyHex = "BC3736A2F4F6779C59BDCEE36B692153D0A9877CC62A474002DF32E52139F0A0";
        const G2 = curve2.decodePointHex("04" + gxHex + gyHex);
        const n2 = new BigInteger("FFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFF7203DF6B21C6052B53BBF40939D54123", 16);
        return { curve: curve2, G: G2, n: n2 };
      }
      function generateKeyPairHex(a, b, c) {
        const random = a ? new BigInteger(a, b, c) : new BigInteger(n.bitLength(), rng);
        const d = random.mod(n.subtract(BigInteger.ONE)).add(BigInteger.ONE);
        const privateKey = leftPad(d.toString(16), 64);
        const P = G.multiply(d);
        const Px = leftPad(P.getX().toBigInteger().toString(16), 64);
        const Py = leftPad(P.getY().toBigInteger().toString(16), 64);
        const publicKey = "04" + Px + Py;
        return { privateKey, publicKey };
      }
      function compressPublicKeyHex(s) {
        if (s.length !== 130) throw new Error("Invalid public key to compress");
        const len = (s.length - 2) / 2;
        const xHex = s.substr(2, len);
        const y = new BigInteger(s.substr(len + 2, len), 16);
        let prefix = "03";
        if (y.mod(new BigInteger("2")).equals(BigInteger.ZERO)) prefix = "02";
        return prefix + xHex;
      }
      function utf8ToHex(input) {
        input = unescape(encodeURIComponent(input));
        const length = input.length;
        const words = [];
        for (let i = 0; i < length; i++) {
          words[i >>> 2] |= (input.charCodeAt(i) & 255) << 24 - i % 4 * 8;
        }
        const hexChars = [];
        for (let i = 0; i < length; i++) {
          const bite = words[i >>> 2] >>> 24 - i % 4 * 8 & 255;
          hexChars.push((bite >>> 4).toString(16));
          hexChars.push((bite & 15).toString(16));
        }
        return hexChars.join("");
      }
      function leftPad(input, num) {
        if (input.length >= num) return input;
        return new Array(num - input.length + 1).join("0") + input;
      }
      function arrayToHex(arr) {
        const hexChars = [];
        for (let i = 0; i < arr.length; i++) {
          const byte = arr[i] & 255;
          hexChars.push((byte >>> 4).toString(16));
          hexChars.push((byte & 15).toString(16));
        }
        return hexChars.join("");
      }
      function arrayToUtf8(arr) {
        const words = [];
        let j = 0;
        for (let i = 0; i < arr.length * 2; i += 2) {
          words[i >>> 3] |= parseInt(arr[j], 10) << 24 - i % 8 * 4;
          j++;
        }
        try {
          const latin1Chars = [];
          for (let i = 0; i < arr.length; i++) {
            const bite = words[i >>> 2] >>> 24 - i % 4 * 8 & 255;
            latin1Chars.push(String.fromCharCode(bite));
          }
          return decodeURIComponent(escape(latin1Chars.join("")));
        } catch (e) {
          throw new Error("Malformed UTF-8 data");
        }
      }
      function hexToArray(hexStr) {
        const words = [];
        let hexStrLength = hexStr.length;
        if (hexStrLength % 2 !== 0) {
          hexStr = leftPad(hexStr, hexStrLength + 1);
        }
        hexStrLength = hexStr.length;
        for (let i = 0; i < hexStrLength; i += 2) {
          words.push(parseInt(hexStr.substr(i, 2), 16));
        }
        return words;
      }
      function isHexString(str) {
        return typeof str === "string" && str.length > 0 && str.length % 2 === 0 && /^[0-9a-fA-F]+$/.test(str);
      }
      function verifyPublicKey(publicKey) {
        if (typeof publicKey !== "string" || !publicKey) return false;
        let point;
        try {
          point = curve.decodePointHex(publicKey);
        } catch (e) {
          return false;
        }
        if (!point || point.isInfinity()) return false;
        const x = point.getX();
        const y = point.getY();
        return y.square().equals(x.multiply(x.square()).add(x.multiply(curve.a)).add(curve.b));
      }
      function comparePublicKeyHex(publicKey1, publicKey2) {
        if (!verifyPublicKey(publicKey1) || !verifyPublicKey(publicKey2)) return false;
        const point1 = curve.decodePointHex(publicKey1);
        const point2 = curve.decodePointHex(publicKey2);
        return point1.equals(point2);
      }
      module.exports = {
        getGlobalCurve,
        generateEcparam,
        generateKeyPairHex,
        compressPublicKeyHex,
        utf8ToHex,
        leftPad,
        arrayToHex,
        arrayToUtf8,
        hexToArray,
        isHexString,
        verifyPublicKey,
        comparePublicKeyHex
      };
    }
  });

  // node_modules/sm-crypto/src/sm2/sm3.js
  var require_sm3 = __commonJS({
    "node_modules/sm-crypto/src/sm2/sm3.js"(exports, module) {
      var W = new Uint32Array(68);
      var M = new Uint32Array(64);
      function rotl(x, n) {
        const s = n & 31;
        return x << s | x >>> 32 - s;
      }
      function xor(x, y) {
        const result = [];
        for (let i = x.length - 1; i >= 0; i--) result[i] = (x[i] ^ y[i]) & 255;
        return result;
      }
      function P0(X) {
        return X ^ rotl(X, 9) ^ rotl(X, 17);
      }
      function P1(X) {
        return X ^ rotl(X, 15) ^ rotl(X, 23);
      }
      function sm3(array) {
        let len = array.length * 8;
        let k = len % 512;
        k = k >= 448 ? 512 - k % 448 - 1 : 448 - k - 1;
        const kArr = new Array((k - 7) / 8);
        const lenArr = new Array(8);
        for (let i = 0, len2 = kArr.length; i < len2; i++) kArr[i] = 0;
        for (let i = 0, len2 = lenArr.length; i < len2; i++) lenArr[i] = 0;
        len = len.toString(2);
        for (let i = 7; i >= 0; i--) {
          if (len.length > 8) {
            const start = len.length - 8;
            lenArr[i] = parseInt(len.substr(start), 2);
            len = len.substr(0, start);
          } else if (len.length > 0) {
            lenArr[i] = parseInt(len, 2);
            len = "";
          }
        }
        const m = new Uint8Array([...array, 128, ...kArr, ...lenArr]);
        const dataView = new DataView(m.buffer, 0);
        const n = m.length / 64;
        const V = new Uint32Array([1937774191, 1226093241, 388252375, 3666478592, 2842636476, 372324522, 3817729613, 2969243214]);
        for (let i = 0; i < n; i++) {
          W.fill(0);
          M.fill(0);
          const start = 16 * i;
          for (let j = 0; j < 16; j++) {
            W[j] = dataView.getUint32((start + j) * 4, false);
          }
          for (let j = 16; j < 68; j++) {
            W[j] = P1(W[j - 16] ^ W[j - 9] ^ rotl(W[j - 3], 15)) ^ rotl(W[j - 13], 7) ^ W[j - 6];
          }
          for (let j = 0; j < 64; j++) {
            M[j] = W[j] ^ W[j + 4];
          }
          const T1 = 2043430169;
          const T2 = 2055708042;
          let A = V[0];
          let B = V[1];
          let C = V[2];
          let D = V[3];
          let E = V[4];
          let F = V[5];
          let G = V[6];
          let H = V[7];
          let SS1;
          let SS2;
          let TT1;
          let TT2;
          let T;
          for (let j = 0; j < 64; j++) {
            T = j >= 0 && j <= 15 ? T1 : T2;
            SS1 = rotl(rotl(A, 12) + E + rotl(T, j), 7);
            SS2 = SS1 ^ rotl(A, 12);
            TT1 = (j >= 0 && j <= 15 ? A ^ B ^ C : A & B | A & C | B & C) + D + SS2 + M[j];
            TT2 = (j >= 0 && j <= 15 ? E ^ F ^ G : E & F | ~E & G) + H + SS1 + W[j];
            D = C;
            C = rotl(B, 9);
            B = A;
            A = TT1;
            H = G;
            G = rotl(F, 19);
            F = E;
            E = P0(TT2);
          }
          V[0] ^= A;
          V[1] ^= B;
          V[2] ^= C;
          V[3] ^= D;
          V[4] ^= E;
          V[5] ^= F;
          V[6] ^= G;
          V[7] ^= H;
        }
        const result = [];
        for (let i = 0, len2 = V.length; i < len2; i++) {
          const word = V[i];
          result.push((word & 4278190080) >>> 24, (word & 16711680) >>> 16, (word & 65280) >>> 8, word & 255);
        }
        return result;
      }
      var blockLen = 64;
      var iPad = new Uint8Array(blockLen);
      var oPad = new Uint8Array(blockLen);
      for (let i = 0; i < blockLen; i++) {
        iPad[i] = 54;
        oPad[i] = 92;
      }
      function hmac(input, key) {
        if (key.length > blockLen) key = sm3(key);
        while (key.length < blockLen) key.push(0);
        const iPadKey = xor(key, iPad);
        const oPadKey = xor(key, oPad);
        const hash = sm3([...iPadKey, ...input]);
        return sm3([...oPadKey, ...hash]);
      }
      module.exports = {
        sm3,
        hmac
      };
    }
  });

  // node_modules/sm-crypto/src/sm2/index.js
  var require_sm2 = __commonJS({
    "node_modules/sm-crypto/src/sm2/index.js"(exports, module) {
      var { BigInteger } = require_jsbn();
      var { encodeDer, decodeDer } = require_asn1();
      var _ = require_utils();
      var sm3 = require_sm3().sm3;
      var { G, curve, n } = _.generateEcparam();
      var C1C2C3 = 0;
      function doEncrypt(msg, publicKey, cipherMode = 1) {
        if (!_.verifyPublicKey(publicKey)) throw new Error("Invalid public key");
        msg = typeof msg === "string" ? _.hexToArray(_.utf8ToHex(msg)) : Array.prototype.slice.call(msg);
        publicKey = _.getGlobalCurve().decodePointHex(publicKey);
        const keypair = _.generateKeyPairHex();
        const k = new BigInteger(keypair.privateKey, 16);
        let c1 = keypair.publicKey;
        if (c1.length > 128) c1 = c1.substr(c1.length - 128);
        const p = publicKey.multiply(k);
        const x2 = _.hexToArray(_.leftPad(p.getX().toBigInteger().toRadix(16), 64));
        const y2 = _.hexToArray(_.leftPad(p.getY().toBigInteger().toRadix(16), 64));
        const c3 = _.arrayToHex(sm3([].concat(x2, msg, y2)));
        let ct = 1;
        let offset = 0;
        let t = [];
        const z = [].concat(x2, y2);
        const nextT = () => {
          t = sm3([...z, ct >> 24 & 255, ct >> 16 & 255, ct >> 8 & 255, ct & 255]);
          ct++;
          offset = 0;
        };
        nextT();
        for (let i = 0, len = msg.length; i < len; i++) {
          if (offset === t.length) nextT();
          msg[i] ^= t[offset++] & 255;
        }
        const c2 = _.arrayToHex(msg);
        return cipherMode === C1C2C3 ? c1 + c2 + c3 : c1 + c3 + c2;
      }
      function doDecrypt(encryptData, privateKey, cipherMode = 1, {
        output = "string"
      } = {}) {
        if (!_.isHexString(encryptData) || encryptData.length < 128 + 64) {
          return output === "array" ? [] : "";
        }
        privateKey = new BigInteger(privateKey, 16);
        let c3 = encryptData.substr(128, 64);
        let c2 = encryptData.substr(128 + 64);
        if (cipherMode === C1C2C3) {
          c3 = encryptData.substr(encryptData.length - 64);
          c2 = encryptData.substr(128, encryptData.length - 128 - 64);
        }
        const msg = _.hexToArray(c2);
        const c1 = _.getGlobalCurve().decodePointHex("04" + encryptData.substr(0, 128));
        if (!c1 || !_.verifyPublicKey("04" + encryptData.substr(0, 128))) {
          return output === "array" ? [] : "";
        }
        const p = c1.multiply(privateKey);
        const x2 = _.hexToArray(_.leftPad(p.getX().toBigInteger().toRadix(16), 64));
        const y2 = _.hexToArray(_.leftPad(p.getY().toBigInteger().toRadix(16), 64));
        let ct = 1;
        let offset = 0;
        let t = [];
        const z = [].concat(x2, y2);
        const nextT = () => {
          t = sm3([...z, ct >> 24 & 255, ct >> 16 & 255, ct >> 8 & 255, ct & 255]);
          ct++;
          offset = 0;
        };
        nextT();
        for (let i = 0, len = msg.length; i < len; i++) {
          if (offset === t.length) nextT();
          msg[i] ^= t[offset++] & 255;
        }
        const checkC3 = _.arrayToHex(sm3([].concat(x2, msg, y2)));
        if (checkC3 === c3.toLowerCase()) {
          return output === "array" ? msg : _.arrayToUtf8(msg);
        } else {
          return output === "array" ? [] : "";
        }
      }
      function doSignature(msg, privateKey, {
        pointPool,
        der,
        hash = true,
        publicKey,
        userId
      } = {}) {
        let hashHex = typeof msg === "string" ? _.utf8ToHex(msg) : _.arrayToHex(Array.prototype.slice.call(msg));
        if (hash) {
          publicKey = publicKey || getPublicKeyFromPrivateKey(privateKey);
          hashHex = getHash(hashHex, publicKey, userId);
        }
        const dA = new BigInteger(privateKey, 16);
        const e = new BigInteger(hashHex, 16);
        let k = null;
        let r = null;
        let s = null;
        do {
          do {
            let point;
            if (pointPool && pointPool.length) {
              point = pointPool.pop();
            } else {
              point = getPoint();
            }
            k = point.k;
            r = e.add(point.x1).mod(n);
          } while (r.equals(BigInteger.ZERO) || r.add(k).equals(n));
          s = dA.add(BigInteger.ONE).modInverse(n).multiply(k.subtract(r.multiply(dA))).mod(n);
        } while (s.equals(BigInteger.ZERO));
        if (der) return encodeDer(r, s);
        return _.leftPad(r.toString(16), 64) + _.leftPad(s.toString(16), 64);
      }
      function doVerifySignature(msg, signHex, publicKey, { der, hash = true, userId } = {}) {
        if (!_.verifyPublicKey(publicKey)) return false;
        let hashHex = typeof msg === "string" ? _.utf8ToHex(msg) : _.arrayToHex(Array.prototype.slice.call(msg));
        if (hash) {
          hashHex = getHash(hashHex, publicKey, userId);
        }
        let r;
        let s;
        if (der) {
          try {
            const decodeDerObj = decodeDer(signHex);
            r = decodeDerObj.r;
            s = decodeDerObj.s;
          } catch (err) {
            return false;
          }
        } else {
          if (!_.isHexString(signHex) || signHex.length !== 128) return false;
          r = new BigInteger(signHex.substring(0, 64), 16);
          s = new BigInteger(signHex.substring(64), 16);
        }
        const nSubOne = n.subtract(BigInteger.ONE);
        if (r.compareTo(BigInteger.ONE) < 0 || r.compareTo(nSubOne) > 0) return false;
        if (s.compareTo(BigInteger.ONE) < 0 || s.compareTo(nSubOne) > 0) return false;
        const PA = curve.decodePointHex(publicKey);
        if (!PA) return false;
        const e = new BigInteger(hashHex, 16);
        const t = r.add(s).mod(n);
        if (t.equals(BigInteger.ZERO)) return false;
        const x1y1 = G.multiply(s).add(PA.multiply(t));
        const R = e.add(x1y1.getX().toBigInteger()).mod(n);
        return r.equals(R);
      }
      function getHash(hashHex, publicKey, userId = "1234567812345678") {
        userId = _.utf8ToHex(userId);
        const a = _.leftPad(G.curve.a.toBigInteger().toRadix(16), 64);
        const b = _.leftPad(G.curve.b.toBigInteger().toRadix(16), 64);
        const gx = _.leftPad(G.getX().toBigInteger().toRadix(16), 64);
        const gy = _.leftPad(G.getY().toBigInteger().toRadix(16), 64);
        let px;
        let py;
        if (publicKey.length === 128) {
          px = publicKey.substr(0, 64);
          py = publicKey.substr(64, 64);
        } else {
          const point = G.curve.decodePointHex(publicKey);
          px = _.leftPad(point.getX().toBigInteger().toRadix(16), 64);
          py = _.leftPad(point.getY().toBigInteger().toRadix(16), 64);
        }
        const data = _.hexToArray(userId + a + b + gx + gy + px + py);
        const entl = userId.length * 4;
        data.unshift(entl & 255);
        data.unshift(entl >> 8 & 255);
        const z = sm3(data);
        return _.arrayToHex(sm3(z.concat(_.hexToArray(hashHex))));
      }
      function getPublicKeyFromPrivateKey(privateKey) {
        const PA = G.multiply(new BigInteger(privateKey, 16));
        const x = _.leftPad(PA.getX().toBigInteger().toString(16), 64);
        const y = _.leftPad(PA.getY().toBigInteger().toString(16), 64);
        return "04" + x + y;
      }
      function getPoint() {
        const keypair = _.generateKeyPairHex();
        const PA = curve.decodePointHex(keypair.publicKey);
        keypair.k = new BigInteger(keypair.privateKey, 16);
        keypair.x1 = PA.getX().toBigInteger();
        return keypair;
      }
      module.exports = {
        generateKeyPairHex: _.generateKeyPairHex,
        compressPublicKeyHex: _.compressPublicKeyHex,
        comparePublicKeyHex: _.comparePublicKeyHex,
        doEncrypt,
        doDecrypt,
        doSignature,
        doVerifySignature,
        getPublicKeyFromPrivateKey,
        getPoint,
        verifyPublicKey: _.verifyPublicKey
      };
    }
  });

  // node_modules/sm-crypto/src/sm3/index.js
  var require_sm32 = __commonJS({
    "node_modules/sm-crypto/src/sm3/index.js"(exports, module) {
      var { sm3, hmac } = require_sm3();
      function leftPad(input, num) {
        if (input.length >= num) return input;
        return new Array(num - input.length + 1).join("0") + input;
      }
      function ArrayToHex(arr) {
        return arr.map((item) => {
          item = item.toString(16);
          return item.length === 1 ? "0" + item : item;
        }).join("");
      }
      function hexToArray(hexStr) {
        const words = [];
        let hexStrLength = hexStr.length;
        if (hexStrLength % 2 !== 0) {
          hexStr = leftPad(hexStr, hexStrLength + 1);
        }
        hexStrLength = hexStr.length;
        for (let i = 0; i < hexStrLength; i += 2) {
          words.push(parseInt(hexStr.substr(i, 2), 16));
        }
        return words;
      }
      function utf8ToArray(str) {
        const arr = [];
        for (let i = 0, len = str.length; i < len; i++) {
          const point = str.codePointAt(i);
          if (point <= 127) {
            arr.push(point);
          } else if (point <= 2047) {
            arr.push(192 | point >>> 6);
            arr.push(128 | point & 63);
          } else if (point <= 55295 || point >= 57344 && point <= 65535) {
            arr.push(224 | point >>> 12);
            arr.push(128 | point >>> 6 & 63);
            arr.push(128 | point & 63);
          } else if (point >= 65536 && point <= 1114111) {
            i++;
            arr.push(240 | point >>> 18 & 28);
            arr.push(128 | point >>> 12 & 63);
            arr.push(128 | point >>> 6 & 63);
            arr.push(128 | point & 63);
          } else {
            arr.push(point);
            throw new Error("input is not supported");
          }
        }
        return arr;
      }
      module.exports = function(input, options) {
        input = typeof input === "string" ? utf8ToArray(input) : Array.prototype.slice.call(input);
        if (options) {
          const mode = options.mode || "hmac";
          if (mode !== "hmac") throw new Error("invalid mode");
          let key = options.key;
          if (!key) throw new Error("invalid key");
          key = typeof key === "string" ? hexToArray(key) : Array.prototype.slice.call(key);
          return ArrayToHex(hmac(input, key));
        }
        return ArrayToHex(sm3(input));
      };
    }
  });

  // node_modules/sm-crypto/src/sm4/index.js
  var require_sm4 = __commonJS({
    "node_modules/sm-crypto/src/sm4/index.js"(exports, module) {
      var DECRYPT = 0;
      var ROUND = 32;
      var BLOCK = 16;
      var Sbox = [
        214,
        144,
        233,
        254,
        204,
        225,
        61,
        183,
        22,
        182,
        20,
        194,
        40,
        251,
        44,
        5,
        43,
        103,
        154,
        118,
        42,
        190,
        4,
        195,
        170,
        68,
        19,
        38,
        73,
        134,
        6,
        153,
        156,
        66,
        80,
        244,
        145,
        239,
        152,
        122,
        51,
        84,
        11,
        67,
        237,
        207,
        172,
        98,
        228,
        179,
        28,
        169,
        201,
        8,
        232,
        149,
        128,
        223,
        148,
        250,
        117,
        143,
        63,
        166,
        71,
        7,
        167,
        252,
        243,
        115,
        23,
        186,
        131,
        89,
        60,
        25,
        230,
        133,
        79,
        168,
        104,
        107,
        129,
        178,
        113,
        100,
        218,
        139,
        248,
        235,
        15,
        75,
        112,
        86,
        157,
        53,
        30,
        36,
        14,
        94,
        99,
        88,
        209,
        162,
        37,
        34,
        124,
        59,
        1,
        33,
        120,
        135,
        212,
        0,
        70,
        87,
        159,
        211,
        39,
        82,
        76,
        54,
        2,
        231,
        160,
        196,
        200,
        158,
        234,
        191,
        138,
        210,
        64,
        199,
        56,
        181,
        163,
        247,
        242,
        206,
        249,
        97,
        21,
        161,
        224,
        174,
        93,
        164,
        155,
        52,
        26,
        85,
        173,
        147,
        50,
        48,
        245,
        140,
        177,
        227,
        29,
        246,
        226,
        46,
        130,
        102,
        202,
        96,
        192,
        41,
        35,
        171,
        13,
        83,
        78,
        111,
        213,
        219,
        55,
        69,
        222,
        253,
        142,
        47,
        3,
        255,
        106,
        114,
        109,
        108,
        91,
        81,
        141,
        27,
        175,
        146,
        187,
        221,
        188,
        127,
        17,
        217,
        92,
        65,
        31,
        16,
        90,
        216,
        10,
        193,
        49,
        136,
        165,
        205,
        123,
        189,
        45,
        116,
        208,
        18,
        184,
        229,
        180,
        176,
        137,
        105,
        151,
        74,
        12,
        150,
        119,
        126,
        101,
        185,
        241,
        9,
        197,
        110,
        198,
        132,
        24,
        240,
        125,
        236,
        58,
        220,
        77,
        32,
        121,
        238,
        95,
        62,
        215,
        203,
        57,
        72
      ];
      var CK = [
        462357,
        472066609,
        943670861,
        1415275113,
        1886879365,
        2358483617,
        2830087869,
        3301692121,
        3773296373,
        4228057617,
        404694573,
        876298825,
        1347903077,
        1819507329,
        2291111581,
        2762715833,
        3234320085,
        3705924337,
        4177462797,
        337322537,
        808926789,
        1280531041,
        1752135293,
        2223739545,
        2695343797,
        3166948049,
        3638552301,
        4110090761,
        269950501,
        741554753,
        1213159005,
        1684763257
      ];
      function hexToArray(str) {
        const arr = [];
        for (let i = 0, len = str.length; i < len; i += 2) {
          arr.push(parseInt(str.substr(i, 2), 16));
        }
        return arr;
      }
      function ArrayToHex(arr) {
        return arr.map((item) => {
          item = item.toString(16);
          return item.length === 1 ? "0" + item : item;
        }).join("");
      }
      function utf8ToArray(str) {
        const arr = [];
        for (let i = 0, len = str.length; i < len; i++) {
          const point = str.codePointAt(i);
          if (point <= 127) {
            arr.push(point);
          } else if (point <= 2047) {
            arr.push(192 | point >>> 6);
            arr.push(128 | point & 63);
          } else if (point <= 55295 || point >= 57344 && point <= 65535) {
            arr.push(224 | point >>> 12);
            arr.push(128 | point >>> 6 & 63);
            arr.push(128 | point & 63);
          } else if (point >= 65536 && point <= 1114111) {
            i++;
            arr.push(240 | point >>> 18 & 28);
            arr.push(128 | point >>> 12 & 63);
            arr.push(128 | point >>> 6 & 63);
            arr.push(128 | point & 63);
          } else {
            arr.push(point);
            throw new Error("input is not supported");
          }
        }
        return arr;
      }
      function arrayToUtf8(arr) {
        const str = [];
        for (let i = 0, len = arr.length; i < len; i++) {
          if (arr[i] >= 240 && arr[i] <= 247) {
            str.push(String.fromCodePoint(((arr[i] & 7) << 18) + ((arr[i + 1] & 63) << 12) + ((arr[i + 2] & 63) << 6) + (arr[i + 3] & 63)));
            i += 3;
          } else if (arr[i] >= 224 && arr[i] <= 239) {
            str.push(String.fromCodePoint(((arr[i] & 15) << 12) + ((arr[i + 1] & 63) << 6) + (arr[i + 2] & 63)));
            i += 2;
          } else if (arr[i] >= 192 && arr[i] <= 223) {
            str.push(String.fromCodePoint(((arr[i] & 31) << 6) + (arr[i + 1] & 63)));
            i++;
          } else {
            str.push(String.fromCodePoint(arr[i]));
          }
        }
        return str.join("");
      }
      function rotl(x, n) {
        const s = n & 31;
        return x << s | x >>> 32 - s;
      }
      function byteSub(a) {
        return (Sbox[a >>> 24 & 255] & 255) << 24 | (Sbox[a >>> 16 & 255] & 255) << 16 | (Sbox[a >>> 8 & 255] & 255) << 8 | Sbox[a & 255] & 255;
      }
      function l1(b) {
        return b ^ rotl(b, 2) ^ rotl(b, 10) ^ rotl(b, 18) ^ rotl(b, 24);
      }
      function l2(b) {
        return b ^ rotl(b, 13) ^ rotl(b, 23);
      }
      function sms4Crypt(input, output, roundKey) {
        const x = new Array(4);
        const tmp = new Array(4);
        for (let i = 0; i < 4; i++) {
          tmp[0] = input[4 * i] & 255;
          tmp[1] = input[4 * i + 1] & 255;
          tmp[2] = input[4 * i + 2] & 255;
          tmp[3] = input[4 * i + 3] & 255;
          x[i] = tmp[0] << 24 | tmp[1] << 16 | tmp[2] << 8 | tmp[3];
        }
        for (let r = 0, mid; r < 32; r += 4) {
          mid = x[1] ^ x[2] ^ x[3] ^ roundKey[r + 0];
          x[0] ^= l1(byteSub(mid));
          mid = x[2] ^ x[3] ^ x[0] ^ roundKey[r + 1];
          x[1] ^= l1(byteSub(mid));
          mid = x[3] ^ x[0] ^ x[1] ^ roundKey[r + 2];
          x[2] ^= l1(byteSub(mid));
          mid = x[0] ^ x[1] ^ x[2] ^ roundKey[r + 3];
          x[3] ^= l1(byteSub(mid));
        }
        for (let j = 0; j < 16; j += 4) {
          output[j] = x[3 - j / 4] >>> 24 & 255;
          output[j + 1] = x[3 - j / 4] >>> 16 & 255;
          output[j + 2] = x[3 - j / 4] >>> 8 & 255;
          output[j + 3] = x[3 - j / 4] & 255;
        }
      }
      function sms4KeyExt(key, roundKey, cryptFlag) {
        const x = new Array(4);
        const tmp = new Array(4);
        for (let i = 0; i < 4; i++) {
          tmp[0] = key[0 + 4 * i] & 255;
          tmp[1] = key[1 + 4 * i] & 255;
          tmp[2] = key[2 + 4 * i] & 255;
          tmp[3] = key[3 + 4 * i] & 255;
          x[i] = tmp[0] << 24 | tmp[1] << 16 | tmp[2] << 8 | tmp[3];
        }
        x[0] ^= 2746333894;
        x[1] ^= 1453994832;
        x[2] ^= 1736282519;
        x[3] ^= 2993693404;
        for (let r = 0, mid; r < 32; r += 4) {
          mid = x[1] ^ x[2] ^ x[3] ^ CK[r + 0];
          roundKey[r + 0] = x[0] ^= l2(byteSub(mid));
          mid = x[2] ^ x[3] ^ x[0] ^ CK[r + 1];
          roundKey[r + 1] = x[1] ^= l2(byteSub(mid));
          mid = x[3] ^ x[0] ^ x[1] ^ CK[r + 2];
          roundKey[r + 2] = x[2] ^= l2(byteSub(mid));
          mid = x[0] ^ x[1] ^ x[2] ^ CK[r + 3];
          roundKey[r + 3] = x[3] ^= l2(byteSub(mid));
        }
        if (cryptFlag === DECRYPT) {
          for (let r = 0, mid; r < 16; r++) {
            mid = roundKey[r];
            roundKey[r] = roundKey[31 - r];
            roundKey[31 - r] = mid;
          }
        }
      }
      function sm4(inArray, key, cryptFlag, {
        padding = "pkcs#7",
        mode,
        iv = [],
        output = "string"
      } = {}) {
        if (mode === "cbc") {
          if (typeof iv === "string") iv = hexToArray(iv);
          if (iv.length !== 128 / 8) {
            throw new Error("iv is invalid");
          }
        }
        if (typeof key === "string") key = hexToArray(key);
        if (key.length !== 128 / 8) {
          throw new Error("key is invalid");
        }
        if (typeof inArray === "string") {
          if (cryptFlag !== DECRYPT) {
            inArray = utf8ToArray(inArray);
          } else {
            inArray = hexToArray(inArray);
          }
        } else {
          inArray = [...inArray];
        }
        if ((padding === "pkcs#5" || padding === "pkcs#7") && cryptFlag !== DECRYPT) {
          const paddingCount = BLOCK - inArray.length % BLOCK;
          for (let i = 0; i < paddingCount; i++) inArray.push(paddingCount);
        }
        const roundKey = new Array(ROUND);
        sms4KeyExt(key, roundKey, cryptFlag);
        const outArray = [];
        let lastVector = iv;
        let restLen = inArray.length;
        let point = 0;
        while (restLen >= BLOCK) {
          const input = inArray.slice(point, point + 16);
          const output2 = new Array(16);
          if (mode === "cbc") {
            for (let i = 0; i < BLOCK; i++) {
              if (cryptFlag !== DECRYPT) {
                input[i] ^= lastVector[i];
              }
            }
          }
          sms4Crypt(input, output2, roundKey);
          for (let i = 0; i < BLOCK; i++) {
            if (mode === "cbc") {
              if (cryptFlag === DECRYPT) {
                output2[i] ^= lastVector[i];
              }
            }
            outArray[point + i] = output2[i];
          }
          if (mode === "cbc") {
            if (cryptFlag !== DECRYPT) {
              lastVector = output2;
            } else {
              lastVector = input;
            }
          }
          restLen -= BLOCK;
          point += BLOCK;
        }
        if ((padding === "pkcs#5" || padding === "pkcs#7") && cryptFlag === DECRYPT) {
          const len = outArray.length;
          const paddingCount = outArray[len - 1];
          for (let i = 1; i <= paddingCount; i++) {
            if (outArray[len - i] !== paddingCount) throw new Error("padding is invalid");
          }
          outArray.splice(len - paddingCount, paddingCount);
        }
        if (output !== "array") {
          if (cryptFlag !== DECRYPT) {
            return ArrayToHex(outArray);
          } else {
            return arrayToUtf8(outArray);
          }
        } else {
          return outArray;
        }
      }
      module.exports = {
        encrypt(inArray, key, options) {
          return sm4(inArray, key, 1, options);
        },
        decrypt(inArray, key, options) {
          return sm4(inArray, key, 0, options);
        }
      };
    }
  });

  // node_modules/sm-crypto/src/index.js
  var require_src = __commonJS({
    "node_modules/sm-crypto/src/index.js"(exports, module) {
      module.exports = {
        sm2: require_sm2(),
        sm3: require_sm32(),
        sm4: require_sm4()
      };
    }
  });

  // node_modules/aes-js/index.js
  var require_aes_js = __commonJS({
    "node_modules/aes-js/index.js"(exports, module) {
      (function(root) {
        "use strict";
        function checkInt(value) {
          return parseInt(value) === value;
        }
        function checkInts(arrayish) {
          if (!checkInt(arrayish.length)) {
            return false;
          }
          for (var i = 0; i < arrayish.length; i++) {
            if (!checkInt(arrayish[i]) || arrayish[i] < 0 || arrayish[i] > 255) {
              return false;
            }
          }
          return true;
        }
        function coerceArray(arg, copy) {
          if (arg.buffer && arg.name === "Uint8Array") {
            if (copy) {
              if (arg.slice) {
                arg = arg.slice();
              } else {
                arg = Array.prototype.slice.call(arg);
              }
            }
            return arg;
          }
          if (Array.isArray(arg)) {
            if (!checkInts(arg)) {
              throw new Error("Array contains invalid value: " + arg);
            }
            return new Uint8Array(arg);
          }
          if (checkInt(arg.length) && checkInts(arg)) {
            return new Uint8Array(arg);
          }
          throw new Error("unsupported array-like object");
        }
        function createArray(length) {
          return new Uint8Array(length);
        }
        function copyArray(sourceArray, targetArray, targetStart, sourceStart, sourceEnd) {
          if (sourceStart != null || sourceEnd != null) {
            if (sourceArray.slice) {
              sourceArray = sourceArray.slice(sourceStart, sourceEnd);
            } else {
              sourceArray = Array.prototype.slice.call(sourceArray, sourceStart, sourceEnd);
            }
          }
          targetArray.set(sourceArray, targetStart);
        }
        var convertUtf8 = /* @__PURE__ */ (function() {
          function toBytes(text) {
            var result = [], i = 0;
            text = encodeURI(text);
            while (i < text.length) {
              var c = text.charCodeAt(i++);
              if (c === 37) {
                result.push(parseInt(text.substr(i, 2), 16));
                i += 2;
              } else {
                result.push(c);
              }
            }
            return coerceArray(result);
          }
          function fromBytes(bytes) {
            var result = [], i = 0;
            while (i < bytes.length) {
              var c = bytes[i];
              if (c < 128) {
                result.push(String.fromCharCode(c));
                i++;
              } else if (c > 191 && c < 224) {
                result.push(String.fromCharCode((c & 31) << 6 | bytes[i + 1] & 63));
                i += 2;
              } else {
                result.push(String.fromCharCode((c & 15) << 12 | (bytes[i + 1] & 63) << 6 | bytes[i + 2] & 63));
                i += 3;
              }
            }
            return result.join("");
          }
          return {
            toBytes,
            fromBytes
          };
        })();
        var convertHex = /* @__PURE__ */ (function() {
          function toBytes(text) {
            var result = [];
            for (var i = 0; i < text.length; i += 2) {
              result.push(parseInt(text.substr(i, 2), 16));
            }
            return result;
          }
          var Hex = "0123456789abcdef";
          function fromBytes(bytes) {
            var result = [];
            for (var i = 0; i < bytes.length; i++) {
              var v = bytes[i];
              result.push(Hex[(v & 240) >> 4] + Hex[v & 15]);
            }
            return result.join("");
          }
          return {
            toBytes,
            fromBytes
          };
        })();
        var numberOfRounds = { 16: 10, 24: 12, 32: 14 };
        var rcon = [1, 2, 4, 8, 16, 32, 64, 128, 27, 54, 108, 216, 171, 77, 154, 47, 94, 188, 99, 198, 151, 53, 106, 212, 179, 125, 250, 239, 197, 145];
        var S = [99, 124, 119, 123, 242, 107, 111, 197, 48, 1, 103, 43, 254, 215, 171, 118, 202, 130, 201, 125, 250, 89, 71, 240, 173, 212, 162, 175, 156, 164, 114, 192, 183, 253, 147, 38, 54, 63, 247, 204, 52, 165, 229, 241, 113, 216, 49, 21, 4, 199, 35, 195, 24, 150, 5, 154, 7, 18, 128, 226, 235, 39, 178, 117, 9, 131, 44, 26, 27, 110, 90, 160, 82, 59, 214, 179, 41, 227, 47, 132, 83, 209, 0, 237, 32, 252, 177, 91, 106, 203, 190, 57, 74, 76, 88, 207, 208, 239, 170, 251, 67, 77, 51, 133, 69, 249, 2, 127, 80, 60, 159, 168, 81, 163, 64, 143, 146, 157, 56, 245, 188, 182, 218, 33, 16, 255, 243, 210, 205, 12, 19, 236, 95, 151, 68, 23, 196, 167, 126, 61, 100, 93, 25, 115, 96, 129, 79, 220, 34, 42, 144, 136, 70, 238, 184, 20, 222, 94, 11, 219, 224, 50, 58, 10, 73, 6, 36, 92, 194, 211, 172, 98, 145, 149, 228, 121, 231, 200, 55, 109, 141, 213, 78, 169, 108, 86, 244, 234, 101, 122, 174, 8, 186, 120, 37, 46, 28, 166, 180, 198, 232, 221, 116, 31, 75, 189, 139, 138, 112, 62, 181, 102, 72, 3, 246, 14, 97, 53, 87, 185, 134, 193, 29, 158, 225, 248, 152, 17, 105, 217, 142, 148, 155, 30, 135, 233, 206, 85, 40, 223, 140, 161, 137, 13, 191, 230, 66, 104, 65, 153, 45, 15, 176, 84, 187, 22];
        var Si = [82, 9, 106, 213, 48, 54, 165, 56, 191, 64, 163, 158, 129, 243, 215, 251, 124, 227, 57, 130, 155, 47, 255, 135, 52, 142, 67, 68, 196, 222, 233, 203, 84, 123, 148, 50, 166, 194, 35, 61, 238, 76, 149, 11, 66, 250, 195, 78, 8, 46, 161, 102, 40, 217, 36, 178, 118, 91, 162, 73, 109, 139, 209, 37, 114, 248, 246, 100, 134, 104, 152, 22, 212, 164, 92, 204, 93, 101, 182, 146, 108, 112, 72, 80, 253, 237, 185, 218, 94, 21, 70, 87, 167, 141, 157, 132, 144, 216, 171, 0, 140, 188, 211, 10, 247, 228, 88, 5, 184, 179, 69, 6, 208, 44, 30, 143, 202, 63, 15, 2, 193, 175, 189, 3, 1, 19, 138, 107, 58, 145, 17, 65, 79, 103, 220, 234, 151, 242, 207, 206, 240, 180, 230, 115, 150, 172, 116, 34, 231, 173, 53, 133, 226, 249, 55, 232, 28, 117, 223, 110, 71, 241, 26, 113, 29, 41, 197, 137, 111, 183, 98, 14, 170, 24, 190, 27, 252, 86, 62, 75, 198, 210, 121, 32, 154, 219, 192, 254, 120, 205, 90, 244, 31, 221, 168, 51, 136, 7, 199, 49, 177, 18, 16, 89, 39, 128, 236, 95, 96, 81, 127, 169, 25, 181, 74, 13, 45, 229, 122, 159, 147, 201, 156, 239, 160, 224, 59, 77, 174, 42, 245, 176, 200, 235, 187, 60, 131, 83, 153, 97, 23, 43, 4, 126, 186, 119, 214, 38, 225, 105, 20, 99, 85, 33, 12, 125];
        var T1 = [3328402341, 4168907908, 4000806809, 4135287693, 4294111757, 3597364157, 3731845041, 2445657428, 1613770832, 33620227, 3462883241, 1445669757, 3892248089, 3050821474, 1303096294, 3967186586, 2412431941, 528646813, 2311702848, 4202528135, 4026202645, 2992200171, 2387036105, 4226871307, 1101901292, 3017069671, 1604494077, 1169141738, 597466303, 1403299063, 3832705686, 2613100635, 1974974402, 3791519004, 1033081774, 1277568618, 1815492186, 2118074177, 4126668546, 2211236943, 1748251740, 1369810420, 3521504564, 4193382664, 3799085459, 2883115123, 1647391059, 706024767, 134480908, 2512897874, 1176707941, 2646852446, 806885416, 932615841, 168101135, 798661301, 235341577, 605164086, 461406363, 3756188221, 3454790438, 1311188841, 2142417613, 3933566367, 302582043, 495158174, 1479289972, 874125870, 907746093, 3698224818, 3025820398, 1537253627, 2756858614, 1983593293, 3084310113, 2108928974, 1378429307, 3722699582, 1580150641, 327451799, 2790478837, 3117535592, 0, 3253595436, 1075847264, 3825007647, 2041688520, 3059440621, 3563743934, 2378943302, 1740553945, 1916352843, 2487896798, 2555137236, 2958579944, 2244988746, 3151024235, 3320835882, 1336584933, 3992714006, 2252555205, 2588757463, 1714631509, 293963156, 2319795663, 3925473552, 67240454, 4269768577, 2689618160, 2017213508, 631218106, 1269344483, 2723238387, 1571005438, 2151694528, 93294474, 1066570413, 563977660, 1882732616, 4059428100, 1673313503, 2008463041, 2950355573, 1109467491, 537923632, 3858759450, 4260623118, 3218264685, 2177748300, 403442708, 638784309, 3287084079, 3193921505, 899127202, 2286175436, 773265209, 2479146071, 1437050866, 4236148354, 2050833735, 3362022572, 3126681063, 840505643, 3866325909, 3227541664, 427917720, 2655997905, 2749160575, 1143087718, 1412049534, 999329963, 193497219, 2353415882, 3354324521, 1807268051, 672404540, 2816401017, 3160301282, 369822493, 2916866934, 3688947771, 1681011286, 1949973070, 336202270, 2454276571, 201721354, 1210328172, 3093060836, 2680341085, 3184776046, 1135389935, 3294782118, 965841320, 831886756, 3554993207, 4068047243, 3588745010, 2345191491, 1849112409, 3664604599, 26054028, 2983581028, 2622377682, 1235855840, 3630984372, 2891339514, 4092916743, 3488279077, 3395642799, 4101667470, 1202630377, 268961816, 1874508501, 4034427016, 1243948399, 1546530418, 941366308, 1470539505, 1941222599, 2546386513, 3421038627, 2715671932, 3899946140, 1042226977, 2521517021, 1639824860, 227249030, 260737669, 3765465232, 2084453954, 1907733956, 3429263018, 2420656344, 100860677, 4160157185, 470683154, 3261161891, 1781871967, 2924959737, 1773779408, 394692241, 2579611992, 974986535, 664706745, 3655459128, 3958962195, 731420851, 571543859, 3530123707, 2849626480, 126783113, 865375399, 765172662, 1008606754, 361203602, 3387549984, 2278477385, 2857719295, 1344809080, 2782912378, 59542671, 1503764984, 160008576, 437062935, 1707065306, 3622233649, 2218934982, 3496503480, 2185314755, 697932208, 1512910199, 504303377, 2075177163, 2824099068, 1841019862, 739644986];
        var T2 = [2781242211, 2230877308, 2582542199, 2381740923, 234877682, 3184946027, 2984144751, 1418839493, 1348481072, 50462977, 2848876391, 2102799147, 434634494, 1656084439, 3863849899, 2599188086, 1167051466, 2636087938, 1082771913, 2281340285, 368048890, 3954334041, 3381544775, 201060592, 3963727277, 1739838676, 4250903202, 3930435503, 3206782108, 4149453988, 2531553906, 1536934080, 3262494647, 484572669, 2923271059, 1783375398, 1517041206, 1098792767, 49674231, 1334037708, 1550332980, 4098991525, 886171109, 150598129, 2481090929, 1940642008, 1398944049, 1059722517, 201851908, 1385547719, 1699095331, 1587397571, 674240536, 2704774806, 252314885, 3039795866, 151914247, 908333586, 2602270848, 1038082786, 651029483, 1766729511, 3447698098, 2682942837, 454166793, 2652734339, 1951935532, 775166490, 758520603, 3000790638, 4004797018, 4217086112, 4137964114, 1299594043, 1639438038, 3464344499, 2068982057, 1054729187, 1901997871, 2534638724, 4121318227, 1757008337, 0, 750906861, 1614815264, 535035132, 3363418545, 3988151131, 3201591914, 1183697867, 3647454910, 1265776953, 3734260298, 3566750796, 3903871064, 1250283471, 1807470800, 717615087, 3847203498, 384695291, 3313910595, 3617213773, 1432761139, 2484176261, 3481945413, 283769337, 100925954, 2180939647, 4037038160, 1148730428, 3123027871, 3813386408, 4087501137, 4267549603, 3229630528, 2315620239, 2906624658, 3156319645, 1215313976, 82966005, 3747855548, 3245848246, 1974459098, 1665278241, 807407632, 451280895, 251524083, 1841287890, 1283575245, 337120268, 891687699, 801369324, 3787349855, 2721421207, 3431482436, 959321879, 1469301956, 4065699751, 2197585534, 1199193405, 2898814052, 3887750493, 724703513, 2514908019, 2696962144, 2551808385, 3516813135, 2141445340, 1715741218, 2119445034, 2872807568, 2198571144, 3398190662, 700968686, 3547052216, 1009259540, 2041044702, 3803995742, 487983883, 1991105499, 1004265696, 1449407026, 1316239930, 504629770, 3683797321, 168560134, 1816667172, 3837287516, 1570751170, 1857934291, 4014189740, 2797888098, 2822345105, 2754712981, 936633572, 2347923833, 852879335, 1133234376, 1500395319, 3084545389, 2348912013, 1689376213, 3533459022, 3762923945, 3034082412, 4205598294, 133428468, 634383082, 2949277029, 2398386810, 3913789102, 403703816, 3580869306, 2297460856, 1867130149, 1918643758, 607656988, 4049053350, 3346248884, 1368901318, 600565992, 2090982877, 2632479860, 557719327, 3717614411, 3697393085, 2249034635, 2232388234, 2430627952, 1115438654, 3295786421, 2865522278, 3633334344, 84280067, 33027830, 303828494, 2747425121, 1600795957, 4188952407, 3496589753, 2434238086, 1486471617, 658119965, 3106381470, 953803233, 334231800, 3005978776, 857870609, 3151128937, 1890179545, 2298973838, 2805175444, 3056442267, 574365214, 2450884487, 550103529, 1233637070, 4289353045, 2018519080, 2057691103, 2399374476, 4166623649, 2148108681, 387583245, 3664101311, 836232934, 3330556482, 3100665960, 3280093505, 2955516313, 2002398509, 287182607, 3413881008, 4238890068, 3597515707, 975967766];
        var T3 = [1671808611, 2089089148, 2006576759, 2072901243, 4061003762, 1807603307, 1873927791, 3310653893, 810573872, 16974337, 1739181671, 729634347, 4263110654, 3613570519, 2883997099, 1989864566, 3393556426, 2191335298, 3376449993, 2106063485, 4195741690, 1508618841, 1204391495, 4027317232, 2917941677, 3563566036, 2734514082, 2951366063, 2629772188, 2767672228, 1922491506, 3227229120, 3082974647, 4246528509, 2477669779, 644500518, 911895606, 1061256767, 4144166391, 3427763148, 878471220, 2784252325, 3845444069, 4043897329, 1905517169, 3631459288, 827548209, 356461077, 67897348, 3344078279, 593839651, 3277757891, 405286936, 2527147926, 84871685, 2595565466, 118033927, 305538066, 2157648768, 3795705826, 3945188843, 661212711, 2999812018, 1973414517, 152769033, 2208177539, 745822252, 439235610, 455947803, 1857215598, 1525593178, 2700827552, 1391895634, 994932283, 3596728278, 3016654259, 695947817, 3812548067, 795958831, 2224493444, 1408607827, 3513301457, 0, 3979133421, 543178784, 4229948412, 2982705585, 1542305371, 1790891114, 3410398667, 3201918910, 961245753, 1256100938, 1289001036, 1491644504, 3477767631, 3496721360, 4012557807, 2867154858, 4212583931, 1137018435, 1305975373, 861234739, 2241073541, 1171229253, 4178635257, 33948674, 2139225727, 1357946960, 1011120188, 2679776671, 2833468328, 1374921297, 2751356323, 1086357568, 2408187279, 2460827538, 2646352285, 944271416, 4110742005, 3168756668, 3066132406, 3665145818, 560153121, 271589392, 4279952895, 4077846003, 3530407890, 3444343245, 202643468, 322250259, 3962553324, 1608629855, 2543990167, 1154254916, 389623319, 3294073796, 2817676711, 2122513534, 1028094525, 1689045092, 1575467613, 422261273, 1939203699, 1621147744, 2174228865, 1339137615, 3699352540, 577127458, 712922154, 2427141008, 2290289544, 1187679302, 3995715566, 3100863416, 339486740, 3732514782, 1591917662, 186455563, 3681988059, 3762019296, 844522546, 978220090, 169743370, 1239126601, 101321734, 611076132, 1558493276, 3260915650, 3547250131, 2901361580, 1655096418, 2443721105, 2510565781, 3828863972, 2039214713, 3878868455, 3359869896, 928607799, 1840765549, 2374762893, 3580146133, 1322425422, 2850048425, 1823791212, 1459268694, 4094161908, 3928346602, 1706019429, 2056189050, 2934523822, 135794696, 3134549946, 2022240376, 628050469, 779246638, 472135708, 2800834470, 3032970164, 3327236038, 3894660072, 3715932637, 1956440180, 522272287, 1272813131, 3185336765, 2340818315, 2323976074, 1888542832, 1044544574, 3049550261, 1722469478, 1222152264, 50660867, 4127324150, 236067854, 1638122081, 895445557, 1475980887, 3117443513, 2257655686, 3243809217, 489110045, 2662934430, 3778599393, 4162055160, 2561878936, 288563729, 1773916777, 3648039385, 2391345038, 2493985684, 2612407707, 505560094, 2274497927, 3911240169, 3460925390, 1442818645, 678973480, 3749357023, 2358182796, 2717407649, 2306869641, 219617805, 3218761151, 3862026214, 1120306242, 1756942440, 1103331905, 2578459033, 762796589, 252780047, 2966125488, 1425844308, 3151392187, 372911126];
        var T4 = [1667474886, 2088535288, 2004326894, 2071694838, 4075949567, 1802223062, 1869591006, 3318043793, 808472672, 16843522, 1734846926, 724270422, 4278065639, 3621216949, 2880169549, 1987484396, 3402253711, 2189597983, 3385409673, 2105378810, 4210693615, 1499065266, 1195886990, 4042263547, 2913856577, 3570689971, 2728590687, 2947541573, 2627518243, 2762274643, 1920112356, 3233831835, 3082273397, 4261223649, 2475929149, 640051788, 909531756, 1061110142, 4160160501, 3435941763, 875846760, 2779116625, 3857003729, 4059105529, 1903268834, 3638064043, 825316194, 353713962, 67374088, 3351728789, 589522246, 3284360861, 404236336, 2526454071, 84217610, 2593830191, 117901582, 303183396, 2155911963, 3806477791, 3958056653, 656894286, 2998062463, 1970642922, 151591698, 2206440989, 741110872, 437923380, 454765878, 1852748508, 1515908788, 2694904667, 1381168804, 993742198, 3604373943, 3014905469, 690584402, 3823320797, 791638366, 2223281939, 1398011302, 3520161977, 0, 3991743681, 538992704, 4244381667, 2981218425, 1532751286, 1785380564, 3419096717, 3200178535, 960056178, 1246420628, 1280103576, 1482221744, 3486468741, 3503319995, 4025428677, 2863326543, 4227536621, 1128514950, 1296947098, 859002214, 2240123921, 1162203018, 4193849577, 33687044, 2139062782, 1347481760, 1010582648, 2678045221, 2829640523, 1364325282, 2745433693, 1077985408, 2408548869, 2459086143, 2644360225, 943212656, 4126475505, 3166494563, 3065430391, 3671750063, 555836226, 269496352, 4294908645, 4092792573, 3537006015, 3452783745, 202118168, 320025894, 3974901699, 1600119230, 2543297077, 1145359496, 387397934, 3301201811, 2812801621, 2122220284, 1027426170, 1684319432, 1566435258, 421079858, 1936954854, 1616945344, 2172753945, 1330631070, 3705438115, 572679748, 707427924, 2425400123, 2290647819, 1179044492, 4008585671, 3099120491, 336870440, 3739122087, 1583276732, 185277718, 3688593069, 3772791771, 842159716, 976899700, 168435220, 1229577106, 101059084, 606366792, 1549591736, 3267517855, 3553849021, 2897014595, 1650632388, 2442242105, 2509612081, 3840161747, 2038008818, 3890688725, 3368567691, 926374254, 1835907034, 2374863873, 3587531953, 1313788572, 2846482505, 1819063512, 1448540844, 4109633523, 3941213647, 1701162954, 2054852340, 2930698567, 134748176, 3132806511, 2021165296, 623210314, 774795868, 471606328, 2795958615, 3031746419, 3334885783, 3907527627, 3722280097, 1953799400, 522133822, 1263263126, 3183336545, 2341176845, 2324333839, 1886425312, 1044267644, 3048588401, 1718004428, 1212733584, 50529542, 4143317495, 235803164, 1633788866, 892690282, 1465383342, 3115962473, 2256965911, 3250673817, 488449850, 2661202215, 3789633753, 4177007595, 2560144171, 286339874, 1768537042, 3654906025, 2391705863, 2492770099, 2610673197, 505291324, 2273808917, 3924369609, 3469625735, 1431699370, 673740880, 3755965093, 2358021891, 2711746649, 2307489801, 218961690, 3217021541, 3873845719, 1111672452, 1751693520, 1094828930, 2576986153, 757954394, 252645662, 2964376443, 1414855848, 3149649517, 370555436];
        var T5 = [1374988112, 2118214995, 437757123, 975658646, 1001089995, 530400753, 2902087851, 1273168787, 540080725, 2910219766, 2295101073, 4110568485, 1340463100, 3307916247, 641025152, 3043140495, 3736164937, 632953703, 1172967064, 1576976609, 3274667266, 2169303058, 2370213795, 1809054150, 59727847, 361929877, 3211623147, 2505202138, 3569255213, 1484005843, 1239443753, 2395588676, 1975683434, 4102977912, 2572697195, 666464733, 3202437046, 4035489047, 3374361702, 2110667444, 1675577880, 3843699074, 2538681184, 1649639237, 2976151520, 3144396420, 4269907996, 4178062228, 1883793496, 2403728665, 2497604743, 1383856311, 2876494627, 1917518562, 3810496343, 1716890410, 3001755655, 800440835, 2261089178, 3543599269, 807962610, 599762354, 33778362, 3977675356, 2328828971, 2809771154, 4077384432, 1315562145, 1708848333, 101039829, 3509871135, 3299278474, 875451293, 2733856160, 92987698, 2767645557, 193195065, 1080094634, 1584504582, 3178106961, 1042385657, 2531067453, 3711829422, 1306967366, 2438237621, 1908694277, 67556463, 1615861247, 429456164, 3602770327, 2302690252, 1742315127, 2968011453, 126454664, 3877198648, 2043211483, 2709260871, 2084704233, 4169408201, 0, 159417987, 841739592, 504459436, 1817866830, 4245618683, 260388950, 1034867998, 908933415, 168810852, 1750902305, 2606453969, 607530554, 202008497, 2472011535, 3035535058, 463180190, 2160117071, 1641816226, 1517767529, 470948374, 3801332234, 3231722213, 1008918595, 303765277, 235474187, 4069246893, 766945465, 337553864, 1475418501, 2943682380, 4003061179, 2743034109, 4144047775, 1551037884, 1147550661, 1543208500, 2336434550, 3408119516, 3069049960, 3102011747, 3610369226, 1113818384, 328671808, 2227573024, 2236228733, 3535486456, 2935566865, 3341394285, 496906059, 3702665459, 226906860, 2009195472, 733156972, 2842737049, 294930682, 1206477858, 2835123396, 2700099354, 1451044056, 573804783, 2269728455, 3644379585, 2362090238, 2564033334, 2801107407, 2776292904, 3669462566, 1068351396, 742039012, 1350078989, 1784663195, 1417561698, 4136440770, 2430122216, 775550814, 2193862645, 2673705150, 1775276924, 1876241833, 3475313331, 3366754619, 270040487, 3902563182, 3678124923, 3441850377, 1851332852, 3969562369, 2203032232, 3868552805, 2868897406, 566021896, 4011190502, 3135740889, 1248802510, 3936291284, 699432150, 832877231, 708780849, 3332740144, 899835584, 1951317047, 4236429990, 3767586992, 866637845, 4043610186, 1106041591, 2144161806, 395441711, 1984812685, 1139781709, 3433712980, 3835036895, 2664543715, 1282050075, 3240894392, 1181045119, 2640243204, 25965917, 4203181171, 4211818798, 3009879386, 2463879762, 3910161971, 1842759443, 2597806476, 933301370, 1509430414, 3943906441, 3467192302, 3076639029, 3776767469, 2051518780, 2631065433, 1441952575, 404016761, 1942435775, 1408749034, 1610459739, 3745345300, 2017778566, 3400528769, 3110650942, 941896748, 3265478751, 371049330, 3168937228, 675039627, 4279080257, 967311729, 135050206, 3635733660, 1683407248, 2076935265, 3576870512, 1215061108, 3501741890];
        var T6 = [1347548327, 1400783205, 3273267108, 2520393566, 3409685355, 4045380933, 2880240216, 2471224067, 1428173050, 4138563181, 2441661558, 636813900, 4233094615, 3620022987, 2149987652, 2411029155, 1239331162, 1730525723, 2554718734, 3781033664, 46346101, 310463728, 2743944855, 3328955385, 3875770207, 2501218972, 3955191162, 3667219033, 768917123, 3545789473, 692707433, 1150208456, 1786102409, 2029293177, 1805211710, 3710368113, 3065962831, 401639597, 1724457132, 3028143674, 409198410, 2196052529, 1620529459, 1164071807, 3769721975, 2226875310, 486441376, 2499348523, 1483753576, 428819965, 2274680428, 3075636216, 598438867, 3799141122, 1474502543, 711349675, 129166120, 53458370, 2592523643, 2782082824, 4063242375, 2988687269, 3120694122, 1559041666, 730517276, 2460449204, 4042459122, 2706270690, 3446004468, 3573941694, 533804130, 2328143614, 2637442643, 2695033685, 839224033, 1973745387, 957055980, 2856345839, 106852767, 1371368976, 4181598602, 1033297158, 2933734917, 1179510461, 3046200461, 91341917, 1862534868, 4284502037, 605657339, 2547432937, 3431546947, 2003294622, 3182487618, 2282195339, 954669403, 3682191598, 1201765386, 3917234703, 3388507166, 0, 2198438022, 1211247597, 2887651696, 1315723890, 4227665663, 1443857720, 507358933, 657861945, 1678381017, 560487590, 3516619604, 975451694, 2970356327, 261314535, 3535072918, 2652609425, 1333838021, 2724322336, 1767536459, 370938394, 182621114, 3854606378, 1128014560, 487725847, 185469197, 2918353863, 3106780840, 3356761769, 2237133081, 1286567175, 3152976349, 4255350624, 2683765030, 3160175349, 3309594171, 878443390, 1988838185, 3704300486, 1756818940, 1673061617, 3403100636, 272786309, 1075025698, 545572369, 2105887268, 4174560061, 296679730, 1841768865, 1260232239, 4091327024, 3960309330, 3497509347, 1814803222, 2578018489, 4195456072, 575138148, 3299409036, 446754879, 3629546796, 4011996048, 3347532110, 3252238545, 4270639778, 915985419, 3483825537, 681933534, 651868046, 2755636671, 3828103837, 223377554, 2607439820, 1649704518, 3270937875, 3901806776, 1580087799, 4118987695, 3198115200, 2087309459, 2842678573, 3016697106, 1003007129, 2802849917, 1860738147, 2077965243, 164439672, 4100872472, 32283319, 2827177882, 1709610350, 2125135846, 136428751, 3874428392, 3652904859, 3460984630, 3572145929, 3593056380, 2939266226, 824852259, 818324884, 3224740454, 930369212, 2801566410, 2967507152, 355706840, 1257309336, 4148292826, 243256656, 790073846, 2373340630, 1296297904, 1422699085, 3756299780, 3818836405, 457992840, 3099667487, 2135319889, 77422314, 1560382517, 1945798516, 788204353, 1521706781, 1385356242, 870912086, 325965383, 2358957921, 2050466060, 2388260884, 2313884476, 4006521127, 901210569, 3990953189, 1014646705, 1503449823, 1062597235, 2031621326, 3212035895, 3931371469, 1533017514, 350174575, 2256028891, 2177544179, 1052338372, 741876788, 1606591296, 1914052035, 213705253, 2334669897, 1107234197, 1899603969, 3725069491, 2631447780, 2422494913, 1635502980, 1893020342, 1950903388, 1120974935];
        var T7 = [2807058932, 1699970625, 2764249623, 1586903591, 1808481195, 1173430173, 1487645946, 59984867, 4199882800, 1844882806, 1989249228, 1277555970, 3623636965, 3419915562, 1149249077, 2744104290, 1514790577, 459744698, 244860394, 3235995134, 1963115311, 4027744588, 2544078150, 4190530515, 1608975247, 2627016082, 2062270317, 1507497298, 2200818878, 567498868, 1764313568, 3359936201, 2305455554, 2037970062, 1047239e3, 1910319033, 1337376481, 2904027272, 2892417312, 984907214, 1243112415, 830661914, 861968209, 2135253587, 2011214180, 2927934315, 2686254721, 731183368, 1750626376, 4246310725, 1820824798, 4172763771, 3542330227, 48394827, 2404901663, 2871682645, 671593195, 3254988725, 2073724613, 145085239, 2280796200, 2779915199, 1790575107, 2187128086, 472615631, 3029510009, 4075877127, 3802222185, 4107101658, 3201631749, 1646252340, 4270507174, 1402811438, 1436590835, 3778151818, 3950355702, 3963161475, 4020912224, 2667994737, 273792366, 2331590177, 104699613, 95345982, 3175501286, 2377486676, 1560637892, 3564045318, 369057872, 4213447064, 3919042237, 1137477952, 2658625497, 1119727848, 2340947849, 1530455833, 4007360968, 172466556, 266959938, 516552836, 0, 2256734592, 3980931627, 1890328081, 1917742170, 4294704398, 945164165, 3575528878, 958871085, 3647212047, 2787207260, 1423022939, 775562294, 1739656202, 3876557655, 2530391278, 2443058075, 3310321856, 547512796, 1265195639, 437656594, 3121275539, 719700128, 3762502690, 387781147, 218828297, 3350065803, 2830708150, 2848461854, 428169201, 122466165, 3720081049, 1627235199, 648017665, 4122762354, 1002783846, 2117360635, 695634755, 3336358691, 4234721005, 4049844452, 3704280881, 2232435299, 574624663, 287343814, 612205898, 1039717051, 840019705, 2708326185, 793451934, 821288114, 1391201670, 3822090177, 376187827, 3113855344, 1224348052, 1679968233, 2361698556, 1058709744, 752375421, 2431590963, 1321699145, 3519142200, 2734591178, 188127444, 2177869557, 3727205754, 2384911031, 3215212461, 2648976442, 2450346104, 3432737375, 1180849278, 331544205, 3102249176, 4150144569, 2952102595, 2159976285, 2474404304, 766078933, 313773861, 2570832044, 2108100632, 1668212892, 3145456443, 2013908262, 418672217, 3070356634, 2594734927, 1852171925, 3867060991, 3473416636, 3907448597, 2614737639, 919489135, 164948639, 2094410160, 2997825956, 590424639, 2486224549, 1723872674, 3157750862, 3399941250, 3501252752, 3625268135, 2555048196, 3673637356, 1343127501, 4130281361, 3599595085, 2957853679, 1297403050, 81781910, 3051593425, 2283490410, 532201772, 1367295589, 3926170974, 895287692, 1953757831, 1093597963, 492483431, 3528626907, 1446242576, 1192455638, 1636604631, 209336225, 344873464, 1015671571, 669961897, 3375740769, 3857572124, 2973530695, 3747192018, 1933530610, 3464042516, 935293895, 3454686199, 2858115069, 1863638845, 3683022916, 4085369519, 3292445032, 875313188, 1080017571, 3279033885, 621591778, 1233856572, 2504130317, 24197544, 3017672716, 3835484340, 3247465558, 2220981195, 3060847922, 1551124588, 1463996600];
        var T8 = [4104605777, 1097159550, 396673818, 660510266, 2875968315, 2638606623, 4200115116, 3808662347, 821712160, 1986918061, 3430322568, 38544885, 3856137295, 718002117, 893681702, 1654886325, 2975484382, 3122358053, 3926825029, 4274053469, 796197571, 1290801793, 1184342925, 3556361835, 2405426947, 2459735317, 1836772287, 1381620373, 3196267988, 1948373848, 3764988233, 3385345166, 3263785589, 2390325492, 1480485785, 3111247143, 3780097726, 2293045232, 548169417, 3459953789, 3746175075, 439452389, 1362321559, 1400849762, 1685577905, 1806599355, 2174754046, 137073913, 1214797936, 1174215055, 3731654548, 2079897426, 1943217067, 1258480242, 529487843, 1437280870, 3945269170, 3049390895, 3313212038, 923313619, 679998e3, 3215307299, 57326082, 377642221, 3474729866, 2041877159, 133361907, 1776460110, 3673476453, 96392454, 878845905, 2801699524, 777231668, 4082475170, 2330014213, 4142626212, 2213296395, 1626319424, 1906247262, 1846563261, 562755902, 3708173718, 1040559837, 3871163981, 1418573201, 3294430577, 114585348, 1343618912, 2566595609, 3186202582, 1078185097, 3651041127, 3896688048, 2307622919, 425408743, 3371096953, 2081048481, 1108339068, 2216610296, 0, 2156299017, 736970802, 292596766, 1517440620, 251657213, 2235061775, 2933202493, 758720310, 265905162, 1554391400, 1532285339, 908999204, 174567692, 1474760595, 4002861748, 2610011675, 3234156416, 3693126241, 2001430874, 303699484, 2478443234, 2687165888, 585122620, 454499602, 151849742, 2345119218, 3064510765, 514443284, 4044981591, 1963412655, 2581445614, 2137062819, 19308535, 1928707164, 1715193156, 4219352155, 1126790795, 600235211, 3992742070, 3841024952, 836553431, 1669664834, 2535604243, 3323011204, 1243905413, 3141400786, 4180808110, 698445255, 2653899549, 2989552604, 2253581325, 3252932727, 3004591147, 1891211689, 2487810577, 3915653703, 4237083816, 4030667424, 2100090966, 865136418, 1229899655, 953270745, 3399679628, 3557504664, 4118925222, 2061379749, 3079546586, 2915017791, 983426092, 2022837584, 1607244650, 2118541908, 2366882550, 3635996816, 972512814, 3283088770, 1568718495, 3499326569, 3576539503, 621982671, 2895723464, 410887952, 2623762152, 1002142683, 645401037, 1494807662, 2595684844, 1335535747, 2507040230, 4293295786, 3167684641, 367585007, 3885750714, 1865862730, 2668221674, 2960971305, 2763173681, 1059270954, 2777952454, 2724642869, 1320957812, 2194319100, 2429595872, 2815956275, 77089521, 3973773121, 3444575871, 2448830231, 1305906550, 4021308739, 2857194700, 2516901860, 3518358430, 1787304780, 740276417, 1699839814, 1592394909, 2352307457, 2272556026, 188821243, 1729977011, 3687994002, 274084841, 3594982253, 3613494426, 2701949495, 4162096729, 322734571, 2837966542, 1640576439, 484830689, 1202797690, 3537852828, 4067639125, 349075736, 3342319475, 4157467219, 4255800159, 1030690015, 1155237496, 2951971274, 1757691577, 607398968, 2738905026, 499347990, 3794078908, 1011452712, 227885567, 2818666809, 213114376, 3034881240, 1455525988, 3414450555, 850817237, 1817998408, 3092726480];
        var U1 = [0, 235474187, 470948374, 303765277, 941896748, 908933415, 607530554, 708780849, 1883793496, 2118214995, 1817866830, 1649639237, 1215061108, 1181045119, 1417561698, 1517767529, 3767586992, 4003061179, 4236429990, 4069246893, 3635733660, 3602770327, 3299278474, 3400528769, 2430122216, 2664543715, 2362090238, 2193862645, 2835123396, 2801107407, 3035535058, 3135740889, 3678124923, 3576870512, 3341394285, 3374361702, 3810496343, 3977675356, 4279080257, 4043610186, 2876494627, 2776292904, 3076639029, 3110650942, 2472011535, 2640243204, 2403728665, 2169303058, 1001089995, 899835584, 666464733, 699432150, 59727847, 226906860, 530400753, 294930682, 1273168787, 1172967064, 1475418501, 1509430414, 1942435775, 2110667444, 1876241833, 1641816226, 2910219766, 2743034109, 2976151520, 3211623147, 2505202138, 2606453969, 2302690252, 2269728455, 3711829422, 3543599269, 3240894392, 3475313331, 3843699074, 3943906441, 4178062228, 4144047775, 1306967366, 1139781709, 1374988112, 1610459739, 1975683434, 2076935265, 1775276924, 1742315127, 1034867998, 866637845, 566021896, 800440835, 92987698, 193195065, 429456164, 395441711, 1984812685, 2017778566, 1784663195, 1683407248, 1315562145, 1080094634, 1383856311, 1551037884, 101039829, 135050206, 437757123, 337553864, 1042385657, 807962610, 573804783, 742039012, 2531067453, 2564033334, 2328828971, 2227573024, 2935566865, 2700099354, 3001755655, 3168937228, 3868552805, 3902563182, 4203181171, 4102977912, 3736164937, 3501741890, 3265478751, 3433712980, 1106041591, 1340463100, 1576976609, 1408749034, 2043211483, 2009195472, 1708848333, 1809054150, 832877231, 1068351396, 766945465, 599762354, 159417987, 126454664, 361929877, 463180190, 2709260871, 2943682380, 3178106961, 3009879386, 2572697195, 2538681184, 2236228733, 2336434550, 3509871135, 3745345300, 3441850377, 3274667266, 3910161971, 3877198648, 4110568485, 4211818798, 2597806476, 2497604743, 2261089178, 2295101073, 2733856160, 2902087851, 3202437046, 2968011453, 3936291284, 3835036895, 4136440770, 4169408201, 3535486456, 3702665459, 3467192302, 3231722213, 2051518780, 1951317047, 1716890410, 1750902305, 1113818384, 1282050075, 1584504582, 1350078989, 168810852, 67556463, 371049330, 404016761, 841739592, 1008918595, 775550814, 540080725, 3969562369, 3801332234, 4035489047, 4269907996, 3569255213, 3669462566, 3366754619, 3332740144, 2631065433, 2463879762, 2160117071, 2395588676, 2767645557, 2868897406, 3102011747, 3069049960, 202008497, 33778362, 270040487, 504459436, 875451293, 975658646, 675039627, 641025152, 2084704233, 1917518562, 1615861247, 1851332852, 1147550661, 1248802510, 1484005843, 1451044056, 933301370, 967311729, 733156972, 632953703, 260388950, 25965917, 328671808, 496906059, 1206477858, 1239443753, 1543208500, 1441952575, 2144161806, 1908694277, 1675577880, 1842759443, 3610369226, 3644379585, 3408119516, 3307916247, 4011190502, 3776767469, 4077384432, 4245618683, 2809771154, 2842737049, 3144396420, 3043140495, 2673705150, 2438237621, 2203032232, 2370213795];
        var U2 = [0, 185469197, 370938394, 487725847, 741876788, 657861945, 975451694, 824852259, 1483753576, 1400783205, 1315723890, 1164071807, 1950903388, 2135319889, 1649704518, 1767536459, 2967507152, 3152976349, 2801566410, 2918353863, 2631447780, 2547432937, 2328143614, 2177544179, 3901806776, 3818836405, 4270639778, 4118987695, 3299409036, 3483825537, 3535072918, 3652904859, 2077965243, 1893020342, 1841768865, 1724457132, 1474502543, 1559041666, 1107234197, 1257309336, 598438867, 681933534, 901210569, 1052338372, 261314535, 77422314, 428819965, 310463728, 3409685355, 3224740454, 3710368113, 3593056380, 3875770207, 3960309330, 4045380933, 4195456072, 2471224067, 2554718734, 2237133081, 2388260884, 3212035895, 3028143674, 2842678573, 2724322336, 4138563181, 4255350624, 3769721975, 3955191162, 3667219033, 3516619604, 3431546947, 3347532110, 2933734917, 2782082824, 3099667487, 3016697106, 2196052529, 2313884476, 2499348523, 2683765030, 1179510461, 1296297904, 1347548327, 1533017514, 1786102409, 1635502980, 2087309459, 2003294622, 507358933, 355706840, 136428751, 53458370, 839224033, 957055980, 605657339, 790073846, 2373340630, 2256028891, 2607439820, 2422494913, 2706270690, 2856345839, 3075636216, 3160175349, 3573941694, 3725069491, 3273267108, 3356761769, 4181598602, 4063242375, 4011996048, 3828103837, 1033297158, 915985419, 730517276, 545572369, 296679730, 446754879, 129166120, 213705253, 1709610350, 1860738147, 1945798516, 2029293177, 1239331162, 1120974935, 1606591296, 1422699085, 4148292826, 4233094615, 3781033664, 3931371469, 3682191598, 3497509347, 3446004468, 3328955385, 2939266226, 2755636671, 3106780840, 2988687269, 2198438022, 2282195339, 2501218972, 2652609425, 1201765386, 1286567175, 1371368976, 1521706781, 1805211710, 1620529459, 2105887268, 1988838185, 533804130, 350174575, 164439672, 46346101, 870912086, 954669403, 636813900, 788204353, 2358957921, 2274680428, 2592523643, 2441661558, 2695033685, 2880240216, 3065962831, 3182487618, 3572145929, 3756299780, 3270937875, 3388507166, 4174560061, 4091327024, 4006521127, 3854606378, 1014646705, 930369212, 711349675, 560487590, 272786309, 457992840, 106852767, 223377554, 1678381017, 1862534868, 1914052035, 2031621326, 1211247597, 1128014560, 1580087799, 1428173050, 32283319, 182621114, 401639597, 486441376, 768917123, 651868046, 1003007129, 818324884, 1503449823, 1385356242, 1333838021, 1150208456, 1973745387, 2125135846, 1673061617, 1756818940, 2970356327, 3120694122, 2802849917, 2887651696, 2637442643, 2520393566, 2334669897, 2149987652, 3917234703, 3799141122, 4284502037, 4100872472, 3309594171, 3460984630, 3545789473, 3629546796, 2050466060, 1899603969, 1814803222, 1730525723, 1443857720, 1560382517, 1075025698, 1260232239, 575138148, 692707433, 878443390, 1062597235, 243256656, 91341917, 409198410, 325965383, 3403100636, 3252238545, 3704300486, 3620022987, 3874428392, 3990953189, 4042459122, 4227665663, 2460449204, 2578018489, 2226875310, 2411029155, 3198115200, 3046200461, 2827177882, 2743944855];
        var U3 = [0, 218828297, 437656594, 387781147, 875313188, 958871085, 775562294, 590424639, 1750626376, 1699970625, 1917742170, 2135253587, 1551124588, 1367295589, 1180849278, 1265195639, 3501252752, 3720081049, 3399941250, 3350065803, 3835484340, 3919042237, 4270507174, 4085369519, 3102249176, 3051593425, 2734591178, 2952102595, 2361698556, 2177869557, 2530391278, 2614737639, 3145456443, 3060847922, 2708326185, 2892417312, 2404901663, 2187128086, 2504130317, 2555048196, 3542330227, 3727205754, 3375740769, 3292445032, 3876557655, 3926170974, 4246310725, 4027744588, 1808481195, 1723872674, 1910319033, 2094410160, 1608975247, 1391201670, 1173430173, 1224348052, 59984867, 244860394, 428169201, 344873464, 935293895, 984907214, 766078933, 547512796, 1844882806, 1627235199, 2011214180, 2062270317, 1507497298, 1423022939, 1137477952, 1321699145, 95345982, 145085239, 532201772, 313773861, 830661914, 1015671571, 731183368, 648017665, 3175501286, 2957853679, 2807058932, 2858115069, 2305455554, 2220981195, 2474404304, 2658625497, 3575528878, 3625268135, 3473416636, 3254988725, 3778151818, 3963161475, 4213447064, 4130281361, 3599595085, 3683022916, 3432737375, 3247465558, 3802222185, 4020912224, 4172763771, 4122762354, 3201631749, 3017672716, 2764249623, 2848461854, 2331590177, 2280796200, 2431590963, 2648976442, 104699613, 188127444, 472615631, 287343814, 840019705, 1058709744, 671593195, 621591778, 1852171925, 1668212892, 1953757831, 2037970062, 1514790577, 1463996600, 1080017571, 1297403050, 3673637356, 3623636965, 3235995134, 3454686199, 4007360968, 3822090177, 4107101658, 4190530515, 2997825956, 3215212461, 2830708150, 2779915199, 2256734592, 2340947849, 2627016082, 2443058075, 172466556, 122466165, 273792366, 492483431, 1047239e3, 861968209, 612205898, 695634755, 1646252340, 1863638845, 2013908262, 1963115311, 1446242576, 1530455833, 1277555970, 1093597963, 1636604631, 1820824798, 2073724613, 1989249228, 1436590835, 1487645946, 1337376481, 1119727848, 164948639, 81781910, 331544205, 516552836, 1039717051, 821288114, 669961897, 719700128, 2973530695, 3157750862, 2871682645, 2787207260, 2232435299, 2283490410, 2667994737, 2450346104, 3647212047, 3564045318, 3279033885, 3464042516, 3980931627, 3762502690, 4150144569, 4199882800, 3070356634, 3121275539, 2904027272, 2686254721, 2200818878, 2384911031, 2570832044, 2486224549, 3747192018, 3528626907, 3310321856, 3359936201, 3950355702, 3867060991, 4049844452, 4234721005, 1739656202, 1790575107, 2108100632, 1890328081, 1402811438, 1586903591, 1233856572, 1149249077, 266959938, 48394827, 369057872, 418672217, 1002783846, 919489135, 567498868, 752375421, 209336225, 24197544, 376187827, 459744698, 945164165, 895287692, 574624663, 793451934, 1679968233, 1764313568, 2117360635, 1933530610, 1343127501, 1560637892, 1243112415, 1192455638, 3704280881, 3519142200, 3336358691, 3419915562, 3907448597, 3857572124, 4075877127, 4294704398, 3029510009, 3113855344, 2927934315, 2744104290, 2159976285, 2377486676, 2594734927, 2544078150];
        var U4 = [0, 151849742, 303699484, 454499602, 607398968, 758720310, 908999204, 1059270954, 1214797936, 1097159550, 1517440620, 1400849762, 1817998408, 1699839814, 2118541908, 2001430874, 2429595872, 2581445614, 2194319100, 2345119218, 3034881240, 3186202582, 2801699524, 2951971274, 3635996816, 3518358430, 3399679628, 3283088770, 4237083816, 4118925222, 4002861748, 3885750714, 1002142683, 850817237, 698445255, 548169417, 529487843, 377642221, 227885567, 77089521, 1943217067, 2061379749, 1640576439, 1757691577, 1474760595, 1592394909, 1174215055, 1290801793, 2875968315, 2724642869, 3111247143, 2960971305, 2405426947, 2253581325, 2638606623, 2487810577, 3808662347, 3926825029, 4044981591, 4162096729, 3342319475, 3459953789, 3576539503, 3693126241, 1986918061, 2137062819, 1685577905, 1836772287, 1381620373, 1532285339, 1078185097, 1229899655, 1040559837, 923313619, 740276417, 621982671, 439452389, 322734571, 137073913, 19308535, 3871163981, 4021308739, 4104605777, 4255800159, 3263785589, 3414450555, 3499326569, 3651041127, 2933202493, 2815956275, 3167684641, 3049390895, 2330014213, 2213296395, 2566595609, 2448830231, 1305906550, 1155237496, 1607244650, 1455525988, 1776460110, 1626319424, 2079897426, 1928707164, 96392454, 213114376, 396673818, 514443284, 562755902, 679998e3, 865136418, 983426092, 3708173718, 3557504664, 3474729866, 3323011204, 4180808110, 4030667424, 3945269170, 3794078908, 2507040230, 2623762152, 2272556026, 2390325492, 2975484382, 3092726480, 2738905026, 2857194700, 3973773121, 3856137295, 4274053469, 4157467219, 3371096953, 3252932727, 3673476453, 3556361835, 2763173681, 2915017791, 3064510765, 3215307299, 2156299017, 2307622919, 2459735317, 2610011675, 2081048481, 1963412655, 1846563261, 1729977011, 1480485785, 1362321559, 1243905413, 1126790795, 878845905, 1030690015, 645401037, 796197571, 274084841, 425408743, 38544885, 188821243, 3613494426, 3731654548, 3313212038, 3430322568, 4082475170, 4200115116, 3780097726, 3896688048, 2668221674, 2516901860, 2366882550, 2216610296, 3141400786, 2989552604, 2837966542, 2687165888, 1202797690, 1320957812, 1437280870, 1554391400, 1669664834, 1787304780, 1906247262, 2022837584, 265905162, 114585348, 499347990, 349075736, 736970802, 585122620, 972512814, 821712160, 2595684844, 2478443234, 2293045232, 2174754046, 3196267988, 3079546586, 2895723464, 2777952454, 3537852828, 3687994002, 3234156416, 3385345166, 4142626212, 4293295786, 3841024952, 3992742070, 174567692, 57326082, 410887952, 292596766, 777231668, 660510266, 1011452712, 893681702, 1108339068, 1258480242, 1343618912, 1494807662, 1715193156, 1865862730, 1948373848, 2100090966, 2701949495, 2818666809, 3004591147, 3122358053, 2235061775, 2352307457, 2535604243, 2653899549, 3915653703, 3764988233, 4219352155, 4067639125, 3444575871, 3294430577, 3746175075, 3594982253, 836553431, 953270745, 600235211, 718002117, 367585007, 484830689, 133361907, 251657213, 2041877159, 1891211689, 1806599355, 1654886325, 1568718495, 1418573201, 1335535747, 1184342925];
        function convertToInt32(bytes) {
          var result = [];
          for (var i = 0; i < bytes.length; i += 4) {
            result.push(
              bytes[i] << 24 | bytes[i + 1] << 16 | bytes[i + 2] << 8 | bytes[i + 3]
            );
          }
          return result;
        }
        var AES = function(key) {
          if (!(this instanceof AES)) {
            throw Error("AES must be instanitated with `new`");
          }
          Object.defineProperty(this, "key", {
            value: coerceArray(key, true)
          });
          this._prepare();
        };
        AES.prototype._prepare = function() {
          var rounds = numberOfRounds[this.key.length];
          if (rounds == null) {
            throw new Error("invalid key size (must be 16, 24 or 32 bytes)");
          }
          this._Ke = [];
          this._Kd = [];
          for (var i = 0; i <= rounds; i++) {
            this._Ke.push([0, 0, 0, 0]);
            this._Kd.push([0, 0, 0, 0]);
          }
          var roundKeyCount = (rounds + 1) * 4;
          var KC = this.key.length / 4;
          var tk = convertToInt32(this.key);
          var index;
          for (var i = 0; i < KC; i++) {
            index = i >> 2;
            this._Ke[index][i % 4] = tk[i];
            this._Kd[rounds - index][i % 4] = tk[i];
          }
          var rconpointer = 0;
          var t = KC, tt;
          while (t < roundKeyCount) {
            tt = tk[KC - 1];
            tk[0] ^= S[tt >> 16 & 255] << 24 ^ S[tt >> 8 & 255] << 16 ^ S[tt & 255] << 8 ^ S[tt >> 24 & 255] ^ rcon[rconpointer] << 24;
            rconpointer += 1;
            if (KC != 8) {
              for (var i = 1; i < KC; i++) {
                tk[i] ^= tk[i - 1];
              }
            } else {
              for (var i = 1; i < KC / 2; i++) {
                tk[i] ^= tk[i - 1];
              }
              tt = tk[KC / 2 - 1];
              tk[KC / 2] ^= S[tt & 255] ^ S[tt >> 8 & 255] << 8 ^ S[tt >> 16 & 255] << 16 ^ S[tt >> 24 & 255] << 24;
              for (var i = KC / 2 + 1; i < KC; i++) {
                tk[i] ^= tk[i - 1];
              }
            }
            var i = 0, r, c;
            while (i < KC && t < roundKeyCount) {
              r = t >> 2;
              c = t % 4;
              this._Ke[r][c] = tk[i];
              this._Kd[rounds - r][c] = tk[i++];
              t++;
            }
          }
          for (var r = 1; r < rounds; r++) {
            for (var c = 0; c < 4; c++) {
              tt = this._Kd[r][c];
              this._Kd[r][c] = U1[tt >> 24 & 255] ^ U2[tt >> 16 & 255] ^ U3[tt >> 8 & 255] ^ U4[tt & 255];
            }
          }
        };
        AES.prototype.encrypt = function(plaintext) {
          if (plaintext.length != 16) {
            throw new Error("invalid plaintext size (must be 16 bytes)");
          }
          var rounds = this._Ke.length - 1;
          var a = [0, 0, 0, 0];
          var t = convertToInt32(plaintext);
          for (var i = 0; i < 4; i++) {
            t[i] ^= this._Ke[0][i];
          }
          for (var r = 1; r < rounds; r++) {
            for (var i = 0; i < 4; i++) {
              a[i] = T1[t[i] >> 24 & 255] ^ T2[t[(i + 1) % 4] >> 16 & 255] ^ T3[t[(i + 2) % 4] >> 8 & 255] ^ T4[t[(i + 3) % 4] & 255] ^ this._Ke[r][i];
            }
            t = a.slice();
          }
          var result = createArray(16), tt;
          for (var i = 0; i < 4; i++) {
            tt = this._Ke[rounds][i];
            result[4 * i] = (S[t[i] >> 24 & 255] ^ tt >> 24) & 255;
            result[4 * i + 1] = (S[t[(i + 1) % 4] >> 16 & 255] ^ tt >> 16) & 255;
            result[4 * i + 2] = (S[t[(i + 2) % 4] >> 8 & 255] ^ tt >> 8) & 255;
            result[4 * i + 3] = (S[t[(i + 3) % 4] & 255] ^ tt) & 255;
          }
          return result;
        };
        AES.prototype.decrypt = function(ciphertext) {
          if (ciphertext.length != 16) {
            throw new Error("invalid ciphertext size (must be 16 bytes)");
          }
          var rounds = this._Kd.length - 1;
          var a = [0, 0, 0, 0];
          var t = convertToInt32(ciphertext);
          for (var i = 0; i < 4; i++) {
            t[i] ^= this._Kd[0][i];
          }
          for (var r = 1; r < rounds; r++) {
            for (var i = 0; i < 4; i++) {
              a[i] = T5[t[i] >> 24 & 255] ^ T6[t[(i + 3) % 4] >> 16 & 255] ^ T7[t[(i + 2) % 4] >> 8 & 255] ^ T8[t[(i + 1) % 4] & 255] ^ this._Kd[r][i];
            }
            t = a.slice();
          }
          var result = createArray(16), tt;
          for (var i = 0; i < 4; i++) {
            tt = this._Kd[rounds][i];
            result[4 * i] = (Si[t[i] >> 24 & 255] ^ tt >> 24) & 255;
            result[4 * i + 1] = (Si[t[(i + 3) % 4] >> 16 & 255] ^ tt >> 16) & 255;
            result[4 * i + 2] = (Si[t[(i + 2) % 4] >> 8 & 255] ^ tt >> 8) & 255;
            result[4 * i + 3] = (Si[t[(i + 1) % 4] & 255] ^ tt) & 255;
          }
          return result;
        };
        var ModeOfOperationECB = function(key) {
          if (!(this instanceof ModeOfOperationECB)) {
            throw Error("AES must be instanitated with `new`");
          }
          this.description = "Electronic Code Block";
          this.name = "ecb";
          this._aes = new AES(key);
        };
        ModeOfOperationECB.prototype.encrypt = function(plaintext) {
          plaintext = coerceArray(plaintext);
          if (plaintext.length % 16 !== 0) {
            throw new Error("invalid plaintext size (must be multiple of 16 bytes)");
          }
          var ciphertext = createArray(plaintext.length);
          var block = createArray(16);
          for (var i = 0; i < plaintext.length; i += 16) {
            copyArray(plaintext, block, 0, i, i + 16);
            block = this._aes.encrypt(block);
            copyArray(block, ciphertext, i);
          }
          return ciphertext;
        };
        ModeOfOperationECB.prototype.decrypt = function(ciphertext) {
          ciphertext = coerceArray(ciphertext);
          if (ciphertext.length % 16 !== 0) {
            throw new Error("invalid ciphertext size (must be multiple of 16 bytes)");
          }
          var plaintext = createArray(ciphertext.length);
          var block = createArray(16);
          for (var i = 0; i < ciphertext.length; i += 16) {
            copyArray(ciphertext, block, 0, i, i + 16);
            block = this._aes.decrypt(block);
            copyArray(block, plaintext, i);
          }
          return plaintext;
        };
        var ModeOfOperationCBC = function(key, iv) {
          if (!(this instanceof ModeOfOperationCBC)) {
            throw Error("AES must be instanitated with `new`");
          }
          this.description = "Cipher Block Chaining";
          this.name = "cbc";
          if (!iv) {
            iv = createArray(16);
          } else if (iv.length != 16) {
            throw new Error("invalid initialation vector size (must be 16 bytes)");
          }
          this._lastCipherblock = coerceArray(iv, true);
          this._aes = new AES(key);
        };
        ModeOfOperationCBC.prototype.encrypt = function(plaintext) {
          plaintext = coerceArray(plaintext);
          if (plaintext.length % 16 !== 0) {
            throw new Error("invalid plaintext size (must be multiple of 16 bytes)");
          }
          var ciphertext = createArray(plaintext.length);
          var block = createArray(16);
          for (var i = 0; i < plaintext.length; i += 16) {
            copyArray(plaintext, block, 0, i, i + 16);
            for (var j = 0; j < 16; j++) {
              block[j] ^= this._lastCipherblock[j];
            }
            this._lastCipherblock = this._aes.encrypt(block);
            copyArray(this._lastCipherblock, ciphertext, i);
          }
          return ciphertext;
        };
        ModeOfOperationCBC.prototype.decrypt = function(ciphertext) {
          ciphertext = coerceArray(ciphertext);
          if (ciphertext.length % 16 !== 0) {
            throw new Error("invalid ciphertext size (must be multiple of 16 bytes)");
          }
          var plaintext = createArray(ciphertext.length);
          var block = createArray(16);
          for (var i = 0; i < ciphertext.length; i += 16) {
            copyArray(ciphertext, block, 0, i, i + 16);
            block = this._aes.decrypt(block);
            for (var j = 0; j < 16; j++) {
              plaintext[i + j] = block[j] ^ this._lastCipherblock[j];
            }
            copyArray(ciphertext, this._lastCipherblock, 0, i, i + 16);
          }
          return plaintext;
        };
        var ModeOfOperationCFB = function(key, iv, segmentSize) {
          if (!(this instanceof ModeOfOperationCFB)) {
            throw Error("AES must be instanitated with `new`");
          }
          this.description = "Cipher Feedback";
          this.name = "cfb";
          if (!iv) {
            iv = createArray(16);
          } else if (iv.length != 16) {
            throw new Error("invalid initialation vector size (must be 16 size)");
          }
          if (!segmentSize) {
            segmentSize = 1;
          }
          this.segmentSize = segmentSize;
          this._shiftRegister = coerceArray(iv, true);
          this._aes = new AES(key);
        };
        ModeOfOperationCFB.prototype.encrypt = function(plaintext) {
          if (plaintext.length % this.segmentSize != 0) {
            throw new Error("invalid plaintext size (must be segmentSize bytes)");
          }
          var encrypted = coerceArray(plaintext, true);
          var xorSegment;
          for (var i = 0; i < encrypted.length; i += this.segmentSize) {
            xorSegment = this._aes.encrypt(this._shiftRegister);
            for (var j = 0; j < this.segmentSize; j++) {
              encrypted[i + j] ^= xorSegment[j];
            }
            copyArray(this._shiftRegister, this._shiftRegister, 0, this.segmentSize);
            copyArray(encrypted, this._shiftRegister, 16 - this.segmentSize, i, i + this.segmentSize);
          }
          return encrypted;
        };
        ModeOfOperationCFB.prototype.decrypt = function(ciphertext) {
          if (ciphertext.length % this.segmentSize != 0) {
            throw new Error("invalid ciphertext size (must be segmentSize bytes)");
          }
          var plaintext = coerceArray(ciphertext, true);
          var xorSegment;
          for (var i = 0; i < plaintext.length; i += this.segmentSize) {
            xorSegment = this._aes.encrypt(this._shiftRegister);
            for (var j = 0; j < this.segmentSize; j++) {
              plaintext[i + j] ^= xorSegment[j];
            }
            copyArray(this._shiftRegister, this._shiftRegister, 0, this.segmentSize);
            copyArray(ciphertext, this._shiftRegister, 16 - this.segmentSize, i, i + this.segmentSize);
          }
          return plaintext;
        };
        var ModeOfOperationOFB = function(key, iv) {
          if (!(this instanceof ModeOfOperationOFB)) {
            throw Error("AES must be instanitated with `new`");
          }
          this.description = "Output Feedback";
          this.name = "ofb";
          if (!iv) {
            iv = createArray(16);
          } else if (iv.length != 16) {
            throw new Error("invalid initialation vector size (must be 16 bytes)");
          }
          this._lastPrecipher = coerceArray(iv, true);
          this._lastPrecipherIndex = 16;
          this._aes = new AES(key);
        };
        ModeOfOperationOFB.prototype.encrypt = function(plaintext) {
          var encrypted = coerceArray(plaintext, true);
          for (var i = 0; i < encrypted.length; i++) {
            if (this._lastPrecipherIndex === 16) {
              this._lastPrecipher = this._aes.encrypt(this._lastPrecipher);
              this._lastPrecipherIndex = 0;
            }
            encrypted[i] ^= this._lastPrecipher[this._lastPrecipherIndex++];
          }
          return encrypted;
        };
        ModeOfOperationOFB.prototype.decrypt = ModeOfOperationOFB.prototype.encrypt;
        var Counter = function(initialValue) {
          if (!(this instanceof Counter)) {
            throw Error("Counter must be instanitated with `new`");
          }
          if (initialValue !== 0 && !initialValue) {
            initialValue = 1;
          }
          if (typeof initialValue === "number") {
            this._counter = createArray(16);
            this.setValue(initialValue);
          } else {
            this.setBytes(initialValue);
          }
        };
        Counter.prototype.setValue = function(value) {
          if (typeof value !== "number" || parseInt(value) != value) {
            throw new Error("invalid counter value (must be an integer)");
          }
          if (value > Number.MAX_SAFE_INTEGER) {
            throw new Error("integer value out of safe range");
          }
          for (var index = 15; index >= 0; --index) {
            this._counter[index] = value % 256;
            value = parseInt(value / 256);
          }
        };
        Counter.prototype.setBytes = function(bytes) {
          bytes = coerceArray(bytes, true);
          if (bytes.length != 16) {
            throw new Error("invalid counter bytes size (must be 16 bytes)");
          }
          this._counter = bytes;
        };
        Counter.prototype.increment = function() {
          for (var i = 15; i >= 0; i--) {
            if (this._counter[i] === 255) {
              this._counter[i] = 0;
            } else {
              this._counter[i]++;
              break;
            }
          }
        };
        var ModeOfOperationCTR = function(key, counter) {
          if (!(this instanceof ModeOfOperationCTR)) {
            throw Error("AES must be instanitated with `new`");
          }
          this.description = "Counter";
          this.name = "ctr";
          if (!(counter instanceof Counter)) {
            counter = new Counter(counter);
          }
          this._counter = counter;
          this._remainingCounter = null;
          this._remainingCounterIndex = 16;
          this._aes = new AES(key);
        };
        ModeOfOperationCTR.prototype.encrypt = function(plaintext) {
          var encrypted = coerceArray(plaintext, true);
          for (var i = 0; i < encrypted.length; i++) {
            if (this._remainingCounterIndex === 16) {
              this._remainingCounter = this._aes.encrypt(this._counter._counter);
              this._remainingCounterIndex = 0;
              this._counter.increment();
            }
            encrypted[i] ^= this._remainingCounter[this._remainingCounterIndex++];
          }
          return encrypted;
        };
        ModeOfOperationCTR.prototype.decrypt = ModeOfOperationCTR.prototype.encrypt;
        function pkcs7pad(data) {
          data = coerceArray(data, true);
          var padder = 16 - data.length % 16;
          var result = createArray(data.length + padder);
          copyArray(data, result);
          for (var i = data.length; i < result.length; i++) {
            result[i] = padder;
          }
          return result;
        }
        function pkcs7strip(data) {
          data = coerceArray(data, true);
          if (data.length < 16) {
            throw new Error("PKCS#7 invalid length");
          }
          var padder = data[data.length - 1];
          if (padder > 16) {
            throw new Error("PKCS#7 padding byte out of range");
          }
          var length = data.length - padder;
          for (var i = 0; i < padder; i++) {
            if (data[length + i] !== padder) {
              throw new Error("PKCS#7 invalid padding byte");
            }
          }
          var result = createArray(length);
          copyArray(data, result, 0, 0, length);
          return result;
        }
        var aesjs = {
          AES,
          Counter,
          ModeOfOperation: {
            ecb: ModeOfOperationECB,
            cbc: ModeOfOperationCBC,
            cfb: ModeOfOperationCFB,
            ofb: ModeOfOperationOFB,
            ctr: ModeOfOperationCTR
          },
          utils: {
            hex: convertHex,
            utf8: convertUtf8
          },
          padding: {
            pkcs7: {
              pad: pkcs7pad,
              strip: pkcs7strip
            }
          },
          _arrayTest: {
            coerceArray,
            createArray,
            copyArray
          }
        };
        if (typeof exports !== "undefined") {
          module.exports = aesjs;
        } else if (typeof define === "function" && define.amd) {
          define([], function() {
            return aesjs;
          });
        } else {
          if (root.aesjs) {
            aesjs._aesjs = root.aesjs;
          }
          root.aesjs = aesjs;
        }
      })(exports);
    }
  });

  // shim-crypto.js
  var require_shim_crypto = __commonJS({
    "shim-crypto.js"(exports, module) {
      var { Buffer: Buffer2 } = require_buffer();
      var md5lib = require_md5();
      var { sm3: sm3hex } = require_src();
      var aesjs = require_aes_js();
      function toBytes(data, enc) {
        if (data == null) return new Uint8Array(0);
        if (data instanceof Uint8Array) return data;
        if (typeof data === "string") {
          if (enc && enc !== "utf8" && enc !== "utf-8") {
            return new Uint8Array(Buffer2.from(data, enc));
          }
          return new Uint8Array(Buffer2.from(data, "utf8"));
        }
        if (Array.isArray(data)) return Uint8Array.from(data);
        return new Uint8Array(data);
      }
      var Hash = class {
        constructor(alg) {
          this.alg = alg;
          this.chunks = [];
        }
        update(data, enc) {
          this.chunks.push(toBytes(data, enc));
          return this;
        }
        digest(enc) {
          let all = Buffer2.concat(this.chunks.map((c) => Buffer2.from(c)));
          let out;
          if (this.alg === "md5") {
            out = Buffer2.from(md5lib.array(all));
          } else if (this.alg === "sm3") {
            out = Buffer2.from(sm3hex(Array.from(all)), "hex");
          } else {
            throw new Error("\u4E0D\u652F\u6301\u7684\u6458\u8981\u7B97\u6CD5: " + this.alg);
          }
          return enc === "hex" ? out.toString("hex") : out;
        }
      };
      var Cipher = class {
        constructor(alg, key, iv) {
          if (alg !== "aes-128-ctr") throw new Error("\u4E0D\u652F\u6301\u7684\u52A0\u5BC6\u7B97\u6CD5: " + alg);
          const k = toBytes(key);
          const v = toBytes(iv);
          if (k.length !== 16) throw new Error("aes-128-ctr \u9700\u8981 16 \u5B57\u8282 key\uFF0C\u5B9E\u9645 " + k.length);
          if (v.length !== 16) throw new Error("aes-128-ctr \u9700\u8981 16 \u5B57\u8282 iv\uFF0C\u5B9E\u9645 " + v.length);
          this.ctr = new aesjs.ModeOfOperation.ctr(k, new aesjs.Counter(v));
        }
        update(data) {
          return Buffer2.from(this.ctr.encrypt(toBytes(data)));
        }
        final() {
          return Buffer2.alloc(0);
        }
      };
      function randomBytes(n) {
        const b = Buffer2.alloc(n);
        const g = globalThis.crypto && globalThis.crypto.getRandomValues;
        if (g) {
          globalThis.crypto.getRandomValues(b);
        } else {
          for (let i = 0; i < n; i++) b[i] = Math.random() * 256 | 0;
        }
        return b;
      }
      function randomInt(max) {
        const b = randomBytes(4);
        const n = (b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]) >>> 0;
        return n % max;
      }
      module.exports = {
        createHash: (alg) => new Hash(String(alg).toLowerCase()),
        createCipheriv: (alg, key, iv) => new Cipher(String(alg).toLowerCase(), key, iv),
        randomBytes,
        randomInt,
        getHashes: () => ["md5", "sm3", "sha1", "sha256"]
      };
    }
  });

  // ../hgw/server/src/util/crypto.js
  var require_crypto = __commonJS({
    "../hgw/server/src/util/crypto.js"(exports, module) {
      "use strict";
      var crypto = require_shim_crypto();
      function toBuf(data) {
        if (Buffer.isBuffer(data)) return data;
        if (data instanceof Uint8Array) return Buffer.from(data);
        if (typeof data === "string") return Buffer.from(data);
        return Buffer.from(data);
      }
      function hex(data) {
        return toBuf(data).toString("hex");
      }
      function unhex(s) {
        const t = String(s).trim();
        if (t.length % 2 !== 0) throw new Error("\u5341\u516D\u8FDB\u5236\u957F\u5EA6\u5FC5\u987B\u4E3A\u5076\u6570");
        if (!/^[0-9a-fA-F]*$/.test(t)) throw new Error("\u975E\u6CD5\u5341\u516D\u8FDB\u5236\u5B57\u7B26");
        return Buffer.from(t, "hex");
      }
      function md5(data) {
        return crypto.createHash("md5").update(toBuf(data)).digest();
      }
      function md5HexUpper(data) {
        return md5(data).toString("hex").toUpperCase();
      }
      function base64Decode(s) {
        return Buffer.from(String(s).trim(), "base64");
      }
      function aes128Ctr(key, counter, data) {
        if (key.length !== 16) throw new Error("content key \u957F\u5EA6\u975E\u6CD5");
        if (counter.length !== 16) throw new Error("CTR \u8BA1\u6570\u5668\u5FC5\u987B 16 \u5B57\u8282");
        const c = crypto.createCipheriv("aes-128-ctr", key, counter);
        return Buffer.concat([c.update(data), c.final()]);
      }
      function popcount(x) {
        let v = x >>> 0;
        v = v - (v >>> 1 & 1431655765);
        v = (v & 858993459) + (v >>> 2 & 858993459);
        v = v + (v >>> 4) & 252645135;
        return v * 16843009 >>> 24;
      }
      module.exports = { hex, unhex, md5, md5HexUpper, base64Decode, aes128Ctr, popcount };
    }
  });

  // ../hgw/server/src/core/thl-sign.js
  var require_thl_sign = __commonJS({
    "../hgw/server/src/core/thl-sign.js"(exports, module) {
      var portableSign = (function() {
        var HongguoApp = (() => {
          var Xt = ((r) => typeof __require < "u" ? __require : typeof Proxy < "u" ? new Proxy(r, { get: (e, t) => (typeof __require < "u" ? __require : e)[t] }) : r)(function(r) {
            if (typeof __require < "u") return __require.apply(this, arguments);
            throw Error('Dynamic require of "' + r + '" is not supported');
          });
          var z = (r, e) => () => (e || r((e = { exports: {} }).exports, e), e.exports);
          var Qt = z((bo, Zt) => {
            "use strict";
            Zt.exports = function(e, t) {
              if (t = t.split(":")[0], e = +e, !e) return false;
              switch (t) {
                case "http":
                case "ws":
                  return e !== 80;
                case "https":
                case "wss":
                  return e !== 443;
                case "ftp":
                  return e !== 21;
                case "gopher":
                  return e !== 70;
                case "file":
                  return false;
              }
              return e !== 0;
            };
          });
          var rr = z((gt) => {
            "use strict";
            var On = Object.prototype.hasOwnProperty, Pn;
            function er(r) {
              try {
                return decodeURIComponent(r.replace(/\+/g, " "));
              } catch (e) {
                return null;
              }
            }
            function tr(r) {
              try {
                return encodeURIComponent(r);
              } catch (e) {
                return null;
              }
            }
            function Mn(r) {
              for (var e = /([^=?#&]+)=?([^&]*)/g, t = {}, n; n = e.exec(r); ) {
                var i = er(n[1]), o = er(n[2]);
                i === null || o === null || i in t || (t[i] = o);
              }
              return t;
            }
            function zn(r, e) {
              e = e || "";
              var t = [], n, i;
              typeof e != "string" && (e = "?");
              for (i in r) if (On.call(r, i)) {
                if (n = r[i], !n && (n === null || n === Pn || isNaN(n)) && (n = ""), i = tr(i), n = tr(n), i === null || n === null) continue;
                t.push(i + "=" + n);
              }
              return t.length ? e + t.join("&") : "";
            }
            gt.stringify = zn;
            gt.parse = Mn;
          });
          var ur = z((wo, fr) => {
            "use strict";
            var ir = Qt(), je = rr(), qn = /^[\x00-\x20\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+/, or = /[\n\r\t]/g, jn = /^[A-Za-z][A-Za-z0-9+-.]*:\/\//, ar = /:\d+$/, Vn = /^([a-z][a-z0-9.+-]*:)?(\/\/)?([\\/]+)?([\S\s]*)/i, $n = /^[a-zA-Z]:/;
            function bt(r) {
              return (r || "").toString().replace(qn, "");
            }
            var mt = [["#", "hash"], ["?", "query"], function(e, t) {
              return ie(t.protocol) ? e.replace(/\\/g, "/") : e;
            }, ["/", "pathname"], ["@", "auth", 1], [NaN, "host", void 0, 1, 1], [/:(\d*)$/, "port", void 0, 1], [NaN, "hostname", void 0, 1, 1]], nr = { hash: 1, query: 1 };
            function cr(r) {
              var e;
              typeof window < "u" ? e = window : typeof global < "u" ? e = global : typeof self < "u" ? e = self : e = {};
              var t = e.location || {};
              r = r || t;
              var n = {}, i = typeof r, o;
              if (r.protocol === "blob:") n = new oe(unescape(r.pathname), {});
              else if (i === "string") {
                n = new oe(r, {});
                for (o in nr) delete n[o];
              } else if (i === "object") {
                for (o in r) o in nr || (n[o] = r[o]);
                n.slashes === void 0 && (n.slashes = jn.test(r.href));
              }
              return n;
            }
            function ie(r) {
              return r === "file:" || r === "ftp:" || r === "http:" || r === "https:" || r === "ws:" || r === "wss:";
            }
            function sr(r, e) {
              r = bt(r), r = r.replace(or, ""), e = e || {};
              var t = Vn.exec(r), n = t[1] ? t[1].toLowerCase() : "", i = !!t[2], o = !!t[3], a = 0, c;
              return i ? o ? (c = t[2] + t[3] + t[4], a = t[2].length + t[3].length) : (c = t[2] + t[4], a = t[2].length) : o ? (c = t[3] + t[4], a = t[3].length) : c = t[4], n === "file:" ? a >= 2 && (c = c.slice(2)) : ie(n) ? c = t[4] : n ? i && (c = c.slice(2)) : a >= 2 && ie(e.protocol) && (c = t[4]), { protocol: n, slashes: i || ie(n), slashesCount: a, rest: c };
            }
            function Wn(r, e) {
              if (r === "") return e;
              for (var t = (e || "/").split("/").slice(0, -1).concat(r.split("/")), n = t.length, i = t[n - 1], o = false, a = 0; n--; ) t[n] === "." ? t.splice(n, 1) : t[n] === ".." ? (t.splice(n, 1), a++) : a && (n === 0 && (o = true), t.splice(n, 1), a--);
              return o && t.unshift(""), (i === "." || i === "..") && t.push(""), t.join("/");
            }
            function oe(r, e, t) {
              if (r = bt(r), r = r.replace(or, ""), !(this instanceof oe)) return new oe(r, e, t);
              var n, i, o, a, c, s, u = mt.slice(), f = typeof e, h = this, d = 0;
              for (f !== "object" && f !== "string" && (t = e, e = null), t && typeof t != "function" && (t = je.parse), e = cr(e), i = sr(r || "", e), n = !i.protocol && !i.slashes, h.slashes = i.slashes || n && e.slashes, h.protocol = i.protocol || e.protocol || "", r = i.rest, (i.protocol === "file:" && (i.slashesCount !== 2 || $n.test(r)) || !i.slashes && (i.protocol || i.slashesCount < 2 || !ie(h.protocol))) && (u[3] = [/(.*)/, "pathname"]); d < u.length; d++) {
                if (a = u[d], typeof a == "function") {
                  r = a(r, h);
                  continue;
                }
                o = a[0], s = a[1], o !== o ? h[s] = r : typeof o == "string" ? (c = o === "@" ? r.lastIndexOf(o) : r.indexOf(o), ~c && (typeof a[2] == "number" ? (h[s] = r.slice(0, c), r = r.slice(c + a[2])) : (h[s] = r.slice(c), r = r.slice(0, c)))) : (c = o.exec(r)) && (h[s] = c[1], r = r.slice(0, c.index)), h[s] = h[s] || n && a[3] && e[s] || "", a[4] && (h[s] = h[s].toLowerCase());
              }
              t && (h.query = t(h.query)), n && e.slashes && h.pathname.charAt(0) !== "/" && (h.pathname !== "" || e.pathname !== "") && (h.pathname = Wn(h.pathname, e.pathname)), h.pathname.charAt(0) !== "/" && ie(h.protocol) && (h.pathname = "/" + h.pathname), ir(h.port, h.protocol) || (h.host = h.hostname, h.port = ""), h.username = h.password = "", h.auth && (c = h.auth.indexOf(":"), ~c ? (h.username = h.auth.slice(0, c), h.username = encodeURIComponent(decodeURIComponent(h.username)), h.password = h.auth.slice(c + 1), h.password = encodeURIComponent(decodeURIComponent(h.password))) : h.username = encodeURIComponent(decodeURIComponent(h.auth)), h.auth = h.password ? h.username + ":" + h.password : h.username), h.origin = h.protocol !== "file:" && ie(h.protocol) && h.host ? h.protocol + "//" + h.host : "null", h.href = h.toString();
            }
            function Jn(r, e, t) {
              var n = this;
              switch (r) {
                case "query":
                  typeof e == "string" && e.length && (e = (t || je.parse)(e)), n[r] = e;
                  break;
                case "port":
                  n[r] = e, ir(e, n.protocol) ? e && (n.host = n.hostname + ":" + e) : (n.host = n.hostname, n[r] = "");
                  break;
                case "hostname":
                  n[r] = e, n.port && (e += ":" + n.port), n.host = e;
                  break;
                case "host":
                  n[r] = e, ar.test(e) ? (e = e.split(":"), n.port = e.pop(), n.hostname = e.join(":")) : (n.hostname = e, n.port = "");
                  break;
                case "protocol":
                  n.protocol = e.toLowerCase(), n.slashes = !t;
                  break;
                case "pathname":
                case "hash":
                  if (e) {
                    var i = r === "pathname" ? "/" : "#";
                    n[r] = e.charAt(0) !== i ? i + e : e;
                  } else n[r] = e;
                  break;
                case "username":
                case "password":
                  n[r] = encodeURIComponent(e);
                  break;
                case "auth":
                  var o = e.indexOf(":");
                  ~o ? (n.username = e.slice(0, o), n.username = encodeURIComponent(decodeURIComponent(n.username)), n.password = e.slice(o + 1), n.password = encodeURIComponent(decodeURIComponent(n.password))) : n.username = encodeURIComponent(decodeURIComponent(e));
              }
              for (var a = 0; a < mt.length; a++) {
                var c = mt[a];
                c[4] && (n[c[1]] = n[c[1]].toLowerCase());
              }
              return n.auth = n.password ? n.username + ":" + n.password : n.username, n.origin = n.protocol !== "file:" && ie(n.protocol) && n.host ? n.protocol + "//" + n.host : "null", n.href = n.toString(), n;
            }
            function Kn(r) {
              (!r || typeof r != "function") && (r = je.stringify);
              var e, t = this, n = t.host, i = t.protocol;
              i && i.charAt(i.length - 1) !== ":" && (i += ":");
              var o = i + (t.protocol && t.slashes || ie(t.protocol) ? "//" : "");
              return t.username ? (o += t.username, t.password && (o += ":" + t.password), o += "@") : t.password ? (o += ":" + t.password, o += "@") : t.protocol !== "file:" && ie(t.protocol) && !n && t.pathname !== "/" && (o += "@"), (n[n.length - 1] === ":" || ar.test(t.hostname) && !t.port) && (n += ":"), o += n + t.pathname, e = typeof t.query == "object" ? r(t.query) : t.query, e && (o += e.charAt(0) !== "?" ? "?" + e : e), t.hash && (o += t.hash), o;
            }
            oe.prototype = { set: Jn, toString: Kn };
            oe.extractProtocol = sr;
            oe.location = cr;
            oe.trimLeft = bt;
            oe.qs = je;
            fr.exports = oe;
          });
          var dr = z((Ve) => {
            "use strict";
            Ve.byteLength = Yn;
            Ve.toByteArray = Zn;
            Ve.fromByteArray = ti;
            var ae = [], Y = [], Gn = typeof Uint8Array < "u" ? Uint8Array : Array, vt = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
            for (xe = 0, hr = vt.length; xe < hr; ++xe) ae[xe] = vt[xe], Y[vt.charCodeAt(xe)] = xe;
            var xe, hr;
            Y[45] = 62;
            Y[95] = 63;
            function lr(r) {
              var e = r.length;
              if (e % 4 > 0) throw new Error("Invalid string. Length must be a multiple of 4");
              var t = r.indexOf("=");
              t === -1 && (t = e);
              var n = t === e ? 0 : 4 - t % 4;
              return [t, n];
            }
            function Yn(r) {
              var e = lr(r), t = e[0], n = e[1];
              return (t + n) * 3 / 4 - n;
            }
            function Xn(r, e, t) {
              return (e + t) * 3 / 4 - t;
            }
            function Zn(r) {
              var e, t = lr(r), n = t[0], i = t[1], o = new Gn(Xn(r, n, i)), a = 0, c = i > 0 ? n - 4 : n, s;
              for (s = 0; s < c; s += 4) e = Y[r.charCodeAt(s)] << 18 | Y[r.charCodeAt(s + 1)] << 12 | Y[r.charCodeAt(s + 2)] << 6 | Y[r.charCodeAt(s + 3)], o[a++] = e >> 16 & 255, o[a++] = e >> 8 & 255, o[a++] = e & 255;
              return i === 2 && (e = Y[r.charCodeAt(s)] << 2 | Y[r.charCodeAt(s + 1)] >> 4, o[a++] = e & 255), i === 1 && (e = Y[r.charCodeAt(s)] << 10 | Y[r.charCodeAt(s + 1)] << 4 | Y[r.charCodeAt(s + 2)] >> 2, o[a++] = e >> 8 & 255, o[a++] = e & 255), o;
            }
            function Qn(r) {
              return ae[r >> 18 & 63] + ae[r >> 12 & 63] + ae[r >> 6 & 63] + ae[r & 63];
            }
            function ei(r, e, t) {
              for (var n, i = [], o = e; o < t; o += 3) n = (r[o] << 16 & 16711680) + (r[o + 1] << 8 & 65280) + (r[o + 2] & 255), i.push(Qn(n));
              return i.join("");
            }
            function ti(r) {
              for (var e, t = r.length, n = t % 3, i = [], o = 16383, a = 0, c = t - n; a < c; a += o) i.push(ei(r, a, a + o > c ? c : a + o));
              return n === 1 ? (e = r[t - 1], i.push(ae[e >> 2] + ae[e << 4 & 63] + "==")) : n === 2 && (e = (r[t - 2] << 8) + r[t - 1], i.push(ae[e >> 10] + ae[e >> 4 & 63] + ae[e << 2 & 63] + "=")), i.join("");
            }
          });
          var pr = z((wt) => {
            wt.read = function(r, e, t, n, i) {
              var o, a, c = i * 8 - n - 1, s = (1 << c) - 1, u = s >> 1, f = -7, h = t ? i - 1 : 0, d = t ? -1 : 1, x = r[e + h];
              for (h += d, o = x & (1 << -f) - 1, x >>= -f, f += c; f > 0; o = o * 256 + r[e + h], h += d, f -= 8) ;
              for (a = o & (1 << -f) - 1, o >>= -f, f += n; f > 0; a = a * 256 + r[e + h], h += d, f -= 8) ;
              if (o === 0) o = 1 - u;
              else {
                if (o === s) return a ? NaN : (x ? -1 : 1) * (1 / 0);
                a = a + Math.pow(2, n), o = o - u;
              }
              return (x ? -1 : 1) * a * Math.pow(2, o - n);
            };
            wt.write = function(r, e, t, n, i, o) {
              var a, c, s, u = o * 8 - i - 1, f = (1 << u) - 1, h = f >> 1, d = i === 23 ? Math.pow(2, -24) - Math.pow(2, -77) : 0, x = n ? 0 : o - 1, y = n ? 1 : -1, I = e < 0 || e === 0 && 1 / e < 0 ? 1 : 0;
              for (e = Math.abs(e), isNaN(e) || e === 1 / 0 ? (c = isNaN(e) ? 1 : 0, a = f) : (a = Math.floor(Math.log(e) / Math.LN2), e * (s = Math.pow(2, -a)) < 1 && (a--, s *= 2), a + h >= 1 ? e += d / s : e += d * Math.pow(2, 1 - h), e * s >= 2 && (a++, s /= 2), a + h >= f ? (c = 0, a = f) : a + h >= 1 ? (c = (e * s - 1) * Math.pow(2, i), a = a + h) : (c = e * Math.pow(2, h - 1) * Math.pow(2, i), a = 0)); i >= 8; r[t + x] = c & 255, x += y, c /= 256, i -= 8) ;
              for (a = a << i | c, u += i; u > 0; r[t + x] = a & 255, x += y, a /= 256, u -= 8) ;
              r[t + x - y] |= I * 128;
            };
          });
          var Je = z((Ie) => {
            "use strict";
            var _t = dr(), Ee = pr(), xr = typeof Symbol == "function" && typeof Symbol.for == "function" ? /* @__PURE__ */ Symbol.for("nodejs.util.inspect.custom") : null;
            Ie.Buffer = m;
            Ie.SlowBuffer = ci;
            Ie.INSPECT_MAX_BYTES = 50;
            var $e = 2147483647;
            Ie.kMaxLength = $e;
            m.TYPED_ARRAY_SUPPORT = ri();
            !m.TYPED_ARRAY_SUPPORT && typeof console < "u" && typeof console.error == "function" && console.error("This browser lacks typed array (Uint8Array) support which is required by `buffer` v5.x. Use `buffer` v4.x if you require old browser support.");
            function ri() {
              try {
                let r = new Uint8Array(1), e = { foo: function() {
                  return 42;
                } };
                return Object.setPrototypeOf(e, Uint8Array.prototype), Object.setPrototypeOf(r, e), r.foo() === 42;
              } catch (e) {
                return false;
              }
            }
            Object.defineProperty(m.prototype, "parent", { enumerable: true, get: function() {
              if (m.isBuffer(this)) return this.buffer;
            } });
            Object.defineProperty(m.prototype, "offset", { enumerable: true, get: function() {
              if (m.isBuffer(this)) return this.byteOffset;
            } });
            function ue(r) {
              if (r > $e) throw new RangeError('The value "' + r + '" is invalid for option "size"');
              let e = new Uint8Array(r);
              return Object.setPrototypeOf(e, m.prototype), e;
            }
            function m(r, e, t) {
              if (typeof r == "number") {
                if (typeof e == "string") throw new TypeError('The "string" argument must be of type string. Received type number');
                return At(r);
              }
              return br(r, e, t);
            }
            m.poolSize = 8192;
            function br(r, e, t) {
              if (typeof r == "string") return ii(r, e);
              if (ArrayBuffer.isView(r)) return oi(r);
              if (r == null) throw new TypeError("The first argument must be one of type string, Buffer, ArrayBuffer, Array, or Array-like Object. Received type " + typeof r);
              if (ce(r, ArrayBuffer) || r && ce(r.buffer, ArrayBuffer) || typeof SharedArrayBuffer < "u" && (ce(r, SharedArrayBuffer) || r && ce(r.buffer, SharedArrayBuffer))) return Bt(r, e, t);
              if (typeof r == "number") throw new TypeError('The "value" argument must not be of type number. Received type number');
              let n = r.valueOf && r.valueOf();
              if (n != null && n !== r) return m.from(n, e, t);
              let i = ai(r);
              if (i) return i;
              if (typeof Symbol < "u" && Symbol.toPrimitive != null && typeof r[Symbol.toPrimitive] == "function") return m.from(r[Symbol.toPrimitive]("string"), e, t);
              throw new TypeError("The first argument must be one of type string, Buffer, ArrayBuffer, Array, or Array-like Object. Received type " + typeof r);
            }
            m.from = function(r, e, t) {
              return br(r, e, t);
            };
            Object.setPrototypeOf(m.prototype, Uint8Array.prototype);
            Object.setPrototypeOf(m, Uint8Array);
            function vr(r) {
              if (typeof r != "number") throw new TypeError('"size" argument must be of type number');
              if (r < 0) throw new RangeError('The value "' + r + '" is invalid for option "size"');
            }
            function ni(r, e, t) {
              return vr(r), r <= 0 ? ue(r) : e !== void 0 ? typeof t == "string" ? ue(r).fill(e, t) : ue(r).fill(e) : ue(r);
            }
            m.alloc = function(r, e, t) {
              return ni(r, e, t);
            };
            function At(r) {
              return vr(r), ue(r < 0 ? 0 : Ct(r) | 0);
            }
            m.allocUnsafe = function(r) {
              return At(r);
            };
            m.allocUnsafeSlow = function(r) {
              return At(r);
            };
            function ii(r, e) {
              if ((typeof e != "string" || e === "") && (e = "utf8"), !m.isEncoding(e)) throw new TypeError("Unknown encoding: " + e);
              let t = wr(r, e) | 0, n = ue(t), i = n.write(r, e);
              return i !== t && (n = n.slice(0, i)), n;
            }
            function Et(r) {
              let e = r.length < 0 ? 0 : Ct(r.length) | 0, t = ue(e);
              for (let n = 0; n < e; n += 1) t[n] = r[n] & 255;
              return t;
            }
            function oi(r) {
              if (ce(r, Uint8Array)) {
                let e = new Uint8Array(r);
                return Bt(e.buffer, e.byteOffset, e.byteLength);
              }
              return Et(r);
            }
            function Bt(r, e, t) {
              if (e < 0 || r.byteLength < e) throw new RangeError('"offset" is outside of buffer bounds');
              if (r.byteLength < e + (t || 0)) throw new RangeError('"length" is outside of buffer bounds');
              let n;
              return e === void 0 && t === void 0 ? n = new Uint8Array(r) : t === void 0 ? n = new Uint8Array(r, e) : n = new Uint8Array(r, e, t), Object.setPrototypeOf(n, m.prototype), n;
            }
            function ai(r) {
              if (m.isBuffer(r)) {
                let e = Ct(r.length) | 0, t = ue(e);
                return t.length === 0 || r.copy(t, 0, 0, e), t;
              }
              if (r.length !== void 0) return typeof r.length != "number" || Ut(r.length) ? ue(0) : Et(r);
              if (r.type === "Buffer" && Array.isArray(r.data)) return Et(r.data);
            }
            function Ct(r) {
              if (r >= $e) throw new RangeError("Attempt to allocate Buffer larger than maximum size: 0x" + $e.toString(16) + " bytes");
              return r | 0;
            }
            function ci(r) {
              return +r != r && (r = 0), m.alloc(+r);
            }
            m.isBuffer = function(e) {
              return e != null && e._isBuffer === true && e !== m.prototype;
            };
            m.compare = function(e, t) {
              if (ce(e, Uint8Array) && (e = m.from(e, e.offset, e.byteLength)), ce(t, Uint8Array) && (t = m.from(t, t.offset, t.byteLength)), !m.isBuffer(e) || !m.isBuffer(t)) throw new TypeError('The "buf1", "buf2" arguments must be one of type Buffer or Uint8Array');
              if (e === t) return 0;
              let n = e.length, i = t.length;
              for (let o = 0, a = Math.min(n, i); o < a; ++o) if (e[o] !== t[o]) {
                n = e[o], i = t[o];
                break;
              }
              return n < i ? -1 : i < n ? 1 : 0;
            };
            m.isEncoding = function(e) {
              switch (String(e).toLowerCase()) {
                case "hex":
                case "utf8":
                case "utf-8":
                case "ascii":
                case "latin1":
                case "binary":
                case "base64":
                case "ucs2":
                case "ucs-2":
                case "utf16le":
                case "utf-16le":
                  return true;
                default:
                  return false;
              }
            };
            m.concat = function(e, t) {
              if (!Array.isArray(e)) throw new TypeError('"list" argument must be an Array of Buffers');
              if (e.length === 0) return m.alloc(0);
              let n;
              if (t === void 0) for (t = 0, n = 0; n < e.length; ++n) t += e[n].length;
              let i = m.allocUnsafe(t), o = 0;
              for (n = 0; n < e.length; ++n) {
                let a = e[n];
                if (ce(a, Uint8Array)) o + a.length > i.length ? (m.isBuffer(a) || (a = m.from(a)), a.copy(i, o)) : Uint8Array.prototype.set.call(i, a, o);
                else if (m.isBuffer(a)) a.copy(i, o);
                else throw new TypeError('"list" argument must be an Array of Buffers');
                o += a.length;
              }
              return i;
            };
            function wr(r, e) {
              if (m.isBuffer(r)) return r.length;
              if (ArrayBuffer.isView(r) || ce(r, ArrayBuffer)) return r.byteLength;
              if (typeof r != "string") throw new TypeError('The "string" argument must be one of type string, Buffer, or ArrayBuffer. Received type ' + typeof r);
              let t = r.length, n = arguments.length > 2 && arguments[2] === true;
              if (!n && t === 0) return 0;
              let i = false;
              for (; ; ) switch (e) {
                case "ascii":
                case "latin1":
                case "binary":
                  return t;
                case "utf8":
                case "utf-8":
                  return It(r).length;
                case "ucs2":
                case "ucs-2":
                case "utf16le":
                case "utf-16le":
                  return t * 2;
                case "hex":
                  return t >>> 1;
                case "base64":
                  return Fr(r).length;
                default:
                  if (i) return n ? -1 : It(r).length;
                  e = ("" + e).toLowerCase(), i = true;
              }
            }
            m.byteLength = wr;
            function si(r, e, t) {
              let n = false;
              if ((e === void 0 || e < 0) && (e = 0), e > this.length || ((t === void 0 || t > this.length) && (t = this.length), t <= 0) || (t >>>= 0, e >>>= 0, t <= e)) return "";
              for (r || (r = "utf8"); ; ) switch (r) {
                case "hex":
                  return mi(this, e, t);
                case "utf8":
                case "utf-8":
                  return Er(this, e, t);
                case "ascii":
                  return yi(this, e, t);
                case "latin1":
                case "binary":
                  return gi(this, e, t);
                case "base64":
                  return pi(this, e, t);
                case "ucs2":
                case "ucs-2":
                case "utf16le":
                case "utf-16le":
                  return bi(this, e, t);
                default:
                  if (n) throw new TypeError("Unknown encoding: " + r);
                  r = (r + "").toLowerCase(), n = true;
              }
            }
            m.prototype._isBuffer = true;
            function ye(r, e, t) {
              let n = r[e];
              r[e] = r[t], r[t] = n;
            }
            m.prototype.swap16 = function() {
              let e = this.length;
              if (e % 2 !== 0) throw new RangeError("Buffer size must be a multiple of 16-bits");
              for (let t = 0; t < e; t += 2) ye(this, t, t + 1);
              return this;
            };
            m.prototype.swap32 = function() {
              let e = this.length;
              if (e % 4 !== 0) throw new RangeError("Buffer size must be a multiple of 32-bits");
              for (let t = 0; t < e; t += 4) ye(this, t, t + 3), ye(this, t + 1, t + 2);
              return this;
            };
            m.prototype.swap64 = function() {
              let e = this.length;
              if (e % 8 !== 0) throw new RangeError("Buffer size must be a multiple of 64-bits");
              for (let t = 0; t < e; t += 8) ye(this, t, t + 7), ye(this, t + 1, t + 6), ye(this, t + 2, t + 5), ye(this, t + 3, t + 4);
              return this;
            };
            m.prototype.toString = function() {
              let e = this.length;
              return e === 0 ? "" : arguments.length === 0 ? Er(this, 0, e) : si.apply(this, arguments);
            };
            m.prototype.toLocaleString = m.prototype.toString;
            m.prototype.equals = function(e) {
              if (!m.isBuffer(e)) throw new TypeError("Argument must be a Buffer");
              return this === e ? true : m.compare(this, e) === 0;
            };
            m.prototype.inspect = function() {
              let e = "", t = Ie.INSPECT_MAX_BYTES;
              return e = this.toString("hex", 0, t).replace(/(.{2})/g, "$1 ").trim(), this.length > t && (e += " ... "), "<Buffer " + e + ">";
            };
            xr && (m.prototype[xr] = m.prototype.inspect);
            m.prototype.compare = function(e, t, n, i, o) {
              if (ce(e, Uint8Array) && (e = m.from(e, e.offset, e.byteLength)), !m.isBuffer(e)) throw new TypeError('The "target" argument must be one of type Buffer or Uint8Array. Received type ' + typeof e);
              if (t === void 0 && (t = 0), n === void 0 && (n = e ? e.length : 0), i === void 0 && (i = 0), o === void 0 && (o = this.length), t < 0 || n > e.length || i < 0 || o > this.length) throw new RangeError("out of range index");
              if (i >= o && t >= n) return 0;
              if (i >= o) return -1;
              if (t >= n) return 1;
              if (t >>>= 0, n >>>= 0, i >>>= 0, o >>>= 0, this === e) return 0;
              let a = o - i, c = n - t, s = Math.min(a, c), u = this.slice(i, o), f = e.slice(t, n);
              for (let h = 0; h < s; ++h) if (u[h] !== f[h]) {
                a = u[h], c = f[h];
                break;
              }
              return a < c ? -1 : c < a ? 1 : 0;
            };
            function _r(r, e, t, n, i) {
              if (r.length === 0) return -1;
              if (typeof t == "string" ? (n = t, t = 0) : t > 2147483647 ? t = 2147483647 : t < -2147483648 && (t = -2147483648), t = +t, Ut(t) && (t = i ? 0 : r.length - 1), t < 0 && (t = r.length + t), t >= r.length) {
                if (i) return -1;
                t = r.length - 1;
              } else if (t < 0) if (i) t = 0;
              else return -1;
              if (typeof e == "string" && (e = m.from(e, n)), m.isBuffer(e)) return e.length === 0 ? -1 : yr(r, e, t, n, i);
              if (typeof e == "number") return e = e & 255, typeof Uint8Array.prototype.indexOf == "function" ? i ? Uint8Array.prototype.indexOf.call(r, e, t) : Uint8Array.prototype.lastIndexOf.call(r, e, t) : yr(r, [e], t, n, i);
              throw new TypeError("val must be string, number or Buffer");
            }
            function yr(r, e, t, n, i) {
              let o = 1, a = r.length, c = e.length;
              if (n !== void 0 && (n = String(n).toLowerCase(), n === "ucs2" || n === "ucs-2" || n === "utf16le" || n === "utf-16le")) {
                if (r.length < 2 || e.length < 2) return -1;
                o = 2, a /= 2, c /= 2, t /= 2;
              }
              function s(f, h) {
                return o === 1 ? f[h] : f.readUInt16BE(h * o);
              }
              let u;
              if (i) {
                let f = -1;
                for (u = t; u < a; u++) if (s(r, u) === s(e, f === -1 ? 0 : u - f)) {
                  if (f === -1 && (f = u), u - f + 1 === c) return f * o;
                } else f !== -1 && (u -= u - f), f = -1;
              } else for (t + c > a && (t = a - c), u = t; u >= 0; u--) {
                let f = true;
                for (let h = 0; h < c; h++) if (s(r, u + h) !== s(e, h)) {
                  f = false;
                  break;
                }
                if (f) return u;
              }
              return -1;
            }
            m.prototype.includes = function(e, t, n) {
              return this.indexOf(e, t, n) !== -1;
            };
            m.prototype.indexOf = function(e, t, n) {
              return _r(this, e, t, n, true);
            };
            m.prototype.lastIndexOf = function(e, t, n) {
              return _r(this, e, t, n, false);
            };
            function fi(r, e, t, n) {
              t = Number(t) || 0;
              let i = r.length - t;
              n ? (n = Number(n), n > i && (n = i)) : n = i;
              let o = e.length;
              n > o / 2 && (n = o / 2);
              let a;
              for (a = 0; a < n; ++a) {
                let c = parseInt(e.substr(a * 2, 2), 16);
                if (Ut(c)) return a;
                r[t + a] = c;
              }
              return a;
            }
            function ui(r, e, t, n) {
              return We(It(e, r.length - t), r, t, n);
            }
            function hi(r, e, t, n) {
              return We(Ei(e), r, t, n);
            }
            function li(r, e, t, n) {
              return We(Fr(e), r, t, n);
            }
            function di(r, e, t, n) {
              return We(Bi(e, r.length - t), r, t, n);
            }
            m.prototype.write = function(e, t, n, i) {
              if (t === void 0) i = "utf8", n = this.length, t = 0;
              else if (n === void 0 && typeof t == "string") i = t, n = this.length, t = 0;
              else if (isFinite(t)) t = t >>> 0, isFinite(n) ? (n = n >>> 0, i === void 0 && (i = "utf8")) : (i = n, n = void 0);
              else throw new Error("Buffer.write(string, encoding, offset[, length]) is no longer supported");
              let o = this.length - t;
              if ((n === void 0 || n > o) && (n = o), e.length > 0 && (n < 0 || t < 0) || t > this.length) throw new RangeError("Attempt to write outside buffer bounds");
              i || (i = "utf8");
              let a = false;
              for (; ; ) switch (i) {
                case "hex":
                  return fi(this, e, t, n);
                case "utf8":
                case "utf-8":
                  return ui(this, e, t, n);
                case "ascii":
                case "latin1":
                case "binary":
                  return hi(this, e, t, n);
                case "base64":
                  return li(this, e, t, n);
                case "ucs2":
                case "ucs-2":
                case "utf16le":
                case "utf-16le":
                  return di(this, e, t, n);
                default:
                  if (a) throw new TypeError("Unknown encoding: " + i);
                  i = ("" + i).toLowerCase(), a = true;
              }
            };
            m.prototype.toJSON = function() {
              return { type: "Buffer", data: Array.prototype.slice.call(this._arr || this, 0) };
            };
            function pi(r, e, t) {
              return e === 0 && t === r.length ? _t.fromByteArray(r) : _t.fromByteArray(r.slice(e, t));
            }
            function Er(r, e, t) {
              t = Math.min(r.length, t);
              let n = [], i = e;
              for (; i < t; ) {
                let o = r[i], a = null, c = o > 239 ? 4 : o > 223 ? 3 : o > 191 ? 2 : 1;
                if (i + c <= t) {
                  let s, u, f, h;
                  switch (c) {
                    case 1:
                      o < 128 && (a = o);
                      break;
                    case 2:
                      s = r[i + 1], (s & 192) === 128 && (h = (o & 31) << 6 | s & 63, h > 127 && (a = h));
                      break;
                    case 3:
                      s = r[i + 1], u = r[i + 2], (s & 192) === 128 && (u & 192) === 128 && (h = (o & 15) << 12 | (s & 63) << 6 | u & 63, h > 2047 && (h < 55296 || h > 57343) && (a = h));
                      break;
                    case 4:
                      s = r[i + 1], u = r[i + 2], f = r[i + 3], (s & 192) === 128 && (u & 192) === 128 && (f & 192) === 128 && (h = (o & 15) << 18 | (s & 63) << 12 | (u & 63) << 6 | f & 63, h > 65535 && h < 1114112 && (a = h));
                  }
                }
                a === null ? (a = 65533, c = 1) : a > 65535 && (a -= 65536, n.push(a >>> 10 & 1023 | 55296), a = 56320 | a & 1023), n.push(a), i += c;
              }
              return xi(n);
            }
            var gr = 4096;
            function xi(r) {
              let e = r.length;
              if (e <= gr) return String.fromCharCode.apply(String, r);
              let t = "", n = 0;
              for (; n < e; ) t += String.fromCharCode.apply(String, r.slice(n, n += gr));
              return t;
            }
            function yi(r, e, t) {
              let n = "";
              t = Math.min(r.length, t);
              for (let i = e; i < t; ++i) n += String.fromCharCode(r[i] & 127);
              return n;
            }
            function gi(r, e, t) {
              let n = "";
              t = Math.min(r.length, t);
              for (let i = e; i < t; ++i) n += String.fromCharCode(r[i]);
              return n;
            }
            function mi(r, e, t) {
              let n = r.length;
              (!e || e < 0) && (e = 0), (!t || t < 0 || t > n) && (t = n);
              let i = "";
              for (let o = e; o < t; ++o) i += Ii[r[o]];
              return i;
            }
            function bi(r, e, t) {
              let n = r.slice(e, t), i = "";
              for (let o = 0; o < n.length - 1; o += 2) i += String.fromCharCode(n[o] + n[o + 1] * 256);
              return i;
            }
            m.prototype.slice = function(e, t) {
              let n = this.length;
              e = ~~e, t = t === void 0 ? n : ~~t, e < 0 ? (e += n, e < 0 && (e = 0)) : e > n && (e = n), t < 0 ? (t += n, t < 0 && (t = 0)) : t > n && (t = n), t < e && (t = e);
              let i = this.subarray(e, t);
              return Object.setPrototypeOf(i, m.prototype), i;
            };
            function j(r, e, t) {
              if (r % 1 !== 0 || r < 0) throw new RangeError("offset is not uint");
              if (r + e > t) throw new RangeError("Trying to access beyond buffer length");
            }
            m.prototype.readUintLE = m.prototype.readUIntLE = function(e, t, n) {
              e = e >>> 0, t = t >>> 0, n || j(e, t, this.length);
              let i = this[e], o = 1, a = 0;
              for (; ++a < t && (o *= 256); ) i += this[e + a] * o;
              return i;
            };
            m.prototype.readUintBE = m.prototype.readUIntBE = function(e, t, n) {
              e = e >>> 0, t = t >>> 0, n || j(e, t, this.length);
              let i = this[e + --t], o = 1;
              for (; t > 0 && (o *= 256); ) i += this[e + --t] * o;
              return i;
            };
            m.prototype.readUint8 = m.prototype.readUInt8 = function(e, t) {
              return e = e >>> 0, t || j(e, 1, this.length), this[e];
            };
            m.prototype.readUint16LE = m.prototype.readUInt16LE = function(e, t) {
              return e = e >>> 0, t || j(e, 2, this.length), this[e] | this[e + 1] << 8;
            };
            m.prototype.readUint16BE = m.prototype.readUInt16BE = function(e, t) {
              return e = e >>> 0, t || j(e, 2, this.length), this[e] << 8 | this[e + 1];
            };
            m.prototype.readUint32LE = m.prototype.readUInt32LE = function(e, t) {
              return e = e >>> 0, t || j(e, 4, this.length), (this[e] | this[e + 1] << 8 | this[e + 2] << 16) + this[e + 3] * 16777216;
            };
            m.prototype.readUint32BE = m.prototype.readUInt32BE = function(e, t) {
              return e = e >>> 0, t || j(e, 4, this.length), this[e] * 16777216 + (this[e + 1] << 16 | this[e + 2] << 8 | this[e + 3]);
            };
            m.prototype.readBigUInt64LE = pe(function(e) {
              e = e >>> 0, Be(e, "offset");
              let t = this[e], n = this[e + 7];
              (t === void 0 || n === void 0) && Le(e, this.length - 8);
              let i = t + this[++e] * 2 ** 8 + this[++e] * 2 ** 16 + this[++e] * 2 ** 24, o = this[++e] + this[++e] * 2 ** 8 + this[++e] * 2 ** 16 + n * 2 ** 24;
              return BigInt(i) + (BigInt(o) << BigInt(32));
            });
            m.prototype.readBigUInt64BE = pe(function(e) {
              e = e >>> 0, Be(e, "offset");
              let t = this[e], n = this[e + 7];
              (t === void 0 || n === void 0) && Le(e, this.length - 8);
              let i = t * 2 ** 24 + this[++e] * 2 ** 16 + this[++e] * 2 ** 8 + this[++e], o = this[++e] * 2 ** 24 + this[++e] * 2 ** 16 + this[++e] * 2 ** 8 + n;
              return (BigInt(i) << BigInt(32)) + BigInt(o);
            });
            m.prototype.readIntLE = function(e, t, n) {
              e = e >>> 0, t = t >>> 0, n || j(e, t, this.length);
              let i = this[e], o = 1, a = 0;
              for (; ++a < t && (o *= 256); ) i += this[e + a] * o;
              return o *= 128, i >= o && (i -= Math.pow(2, 8 * t)), i;
            };
            m.prototype.readIntBE = function(e, t, n) {
              e = e >>> 0, t = t >>> 0, n || j(e, t, this.length);
              let i = t, o = 1, a = this[e + --i];
              for (; i > 0 && (o *= 256); ) a += this[e + --i] * o;
              return o *= 128, a >= o && (a -= Math.pow(2, 8 * t)), a;
            };
            m.prototype.readInt8 = function(e, t) {
              return e = e >>> 0, t || j(e, 1, this.length), this[e] & 128 ? (255 - this[e] + 1) * -1 : this[e];
            };
            m.prototype.readInt16LE = function(e, t) {
              e = e >>> 0, t || j(e, 2, this.length);
              let n = this[e] | this[e + 1] << 8;
              return n & 32768 ? n | 4294901760 : n;
            };
            m.prototype.readInt16BE = function(e, t) {
              e = e >>> 0, t || j(e, 2, this.length);
              let n = this[e + 1] | this[e] << 8;
              return n & 32768 ? n | 4294901760 : n;
            };
            m.prototype.readInt32LE = function(e, t) {
              return e = e >>> 0, t || j(e, 4, this.length), this[e] | this[e + 1] << 8 | this[e + 2] << 16 | this[e + 3] << 24;
            };
            m.prototype.readInt32BE = function(e, t) {
              return e = e >>> 0, t || j(e, 4, this.length), this[e] << 24 | this[e + 1] << 16 | this[e + 2] << 8 | this[e + 3];
            };
            m.prototype.readBigInt64LE = pe(function(e) {
              e = e >>> 0, Be(e, "offset");
              let t = this[e], n = this[e + 7];
              (t === void 0 || n === void 0) && Le(e, this.length - 8);
              let i = this[e + 4] + this[e + 5] * 2 ** 8 + this[e + 6] * 2 ** 16 + (n << 24);
              return (BigInt(i) << BigInt(32)) + BigInt(t + this[++e] * 2 ** 8 + this[++e] * 2 ** 16 + this[++e] * 2 ** 24);
            });
            m.prototype.readBigInt64BE = pe(function(e) {
              e = e >>> 0, Be(e, "offset");
              let t = this[e], n = this[e + 7];
              (t === void 0 || n === void 0) && Le(e, this.length - 8);
              let i = (t << 24) + this[++e] * 2 ** 16 + this[++e] * 2 ** 8 + this[++e];
              return (BigInt(i) << BigInt(32)) + BigInt(this[++e] * 2 ** 24 + this[++e] * 2 ** 16 + this[++e] * 2 ** 8 + n);
            });
            m.prototype.readFloatLE = function(e, t) {
              return e = e >>> 0, t || j(e, 4, this.length), Ee.read(this, e, true, 23, 4);
            };
            m.prototype.readFloatBE = function(e, t) {
              return e = e >>> 0, t || j(e, 4, this.length), Ee.read(this, e, false, 23, 4);
            };
            m.prototype.readDoubleLE = function(e, t) {
              return e = e >>> 0, t || j(e, 8, this.length), Ee.read(this, e, true, 52, 8);
            };
            m.prototype.readDoubleBE = function(e, t) {
              return e = e >>> 0, t || j(e, 8, this.length), Ee.read(this, e, false, 52, 8);
            };
            function V(r, e, t, n, i, o) {
              if (!m.isBuffer(r)) throw new TypeError('"buffer" argument must be a Buffer instance');
              if (e > i || e < o) throw new RangeError('"value" argument is out of bounds');
              if (t + n > r.length) throw new RangeError("Index out of range");
            }
            m.prototype.writeUintLE = m.prototype.writeUIntLE = function(e, t, n, i) {
              if (e = +e, t = t >>> 0, n = n >>> 0, !i) {
                let c = Math.pow(2, 8 * n) - 1;
                V(this, e, t, n, c, 0);
              }
              let o = 1, a = 0;
              for (this[t] = e & 255; ++a < n && (o *= 256); ) this[t + a] = e / o & 255;
              return t + n;
            };
            m.prototype.writeUintBE = m.prototype.writeUIntBE = function(e, t, n, i) {
              if (e = +e, t = t >>> 0, n = n >>> 0, !i) {
                let c = Math.pow(2, 8 * n) - 1;
                V(this, e, t, n, c, 0);
              }
              let o = n - 1, a = 1;
              for (this[t + o] = e & 255; --o >= 0 && (a *= 256); ) this[t + o] = e / a & 255;
              return t + n;
            };
            m.prototype.writeUint8 = m.prototype.writeUInt8 = function(e, t, n) {
              return e = +e, t = t >>> 0, n || V(this, e, t, 1, 255, 0), this[t] = e & 255, t + 1;
            };
            m.prototype.writeUint16LE = m.prototype.writeUInt16LE = function(e, t, n) {
              return e = +e, t = t >>> 0, n || V(this, e, t, 2, 65535, 0), this[t] = e & 255, this[t + 1] = e >>> 8, t + 2;
            };
            m.prototype.writeUint16BE = m.prototype.writeUInt16BE = function(e, t, n) {
              return e = +e, t = t >>> 0, n || V(this, e, t, 2, 65535, 0), this[t] = e >>> 8, this[t + 1] = e & 255, t + 2;
            };
            m.prototype.writeUint32LE = m.prototype.writeUInt32LE = function(e, t, n) {
              return e = +e, t = t >>> 0, n || V(this, e, t, 4, 4294967295, 0), this[t + 3] = e >>> 24, this[t + 2] = e >>> 16, this[t + 1] = e >>> 8, this[t] = e & 255, t + 4;
            };
            m.prototype.writeUint32BE = m.prototype.writeUInt32BE = function(e, t, n) {
              return e = +e, t = t >>> 0, n || V(this, e, t, 4, 4294967295, 0), this[t] = e >>> 24, this[t + 1] = e >>> 16, this[t + 2] = e >>> 8, this[t + 3] = e & 255, t + 4;
            };
            function Br(r, e, t, n, i) {
              Ur(e, n, i, r, t, 7);
              let o = Number(e & BigInt(4294967295));
              r[t++] = o, o = o >> 8, r[t++] = o, o = o >> 8, r[t++] = o, o = o >> 8, r[t++] = o;
              let a = Number(e >> BigInt(32) & BigInt(4294967295));
              return r[t++] = a, a = a >> 8, r[t++] = a, a = a >> 8, r[t++] = a, a = a >> 8, r[t++] = a, t;
            }
            function Ir(r, e, t, n, i) {
              Ur(e, n, i, r, t, 7);
              let o = Number(e & BigInt(4294967295));
              r[t + 7] = o, o = o >> 8, r[t + 6] = o, o = o >> 8, r[t + 5] = o, o = o >> 8, r[t + 4] = o;
              let a = Number(e >> BigInt(32) & BigInt(4294967295));
              return r[t + 3] = a, a = a >> 8, r[t + 2] = a, a = a >> 8, r[t + 1] = a, a = a >> 8, r[t] = a, t + 8;
            }
            m.prototype.writeBigUInt64LE = pe(function(e, t = 0) {
              return Br(this, e, t, BigInt(0), BigInt("0xffffffffffffffff"));
            });
            m.prototype.writeBigUInt64BE = pe(function(e, t = 0) {
              return Ir(this, e, t, BigInt(0), BigInt("0xffffffffffffffff"));
            });
            m.prototype.writeIntLE = function(e, t, n, i) {
              if (e = +e, t = t >>> 0, !i) {
                let s = Math.pow(2, 8 * n - 1);
                V(this, e, t, n, s - 1, -s);
              }
              let o = 0, a = 1, c = 0;
              for (this[t] = e & 255; ++o < n && (a *= 256); ) e < 0 && c === 0 && this[t + o - 1] !== 0 && (c = 1), this[t + o] = (e / a >> 0) - c & 255;
              return t + n;
            };
            m.prototype.writeIntBE = function(e, t, n, i) {
              if (e = +e, t = t >>> 0, !i) {
                let s = Math.pow(2, 8 * n - 1);
                V(this, e, t, n, s - 1, -s);
              }
              let o = n - 1, a = 1, c = 0;
              for (this[t + o] = e & 255; --o >= 0 && (a *= 256); ) e < 0 && c === 0 && this[t + o + 1] !== 0 && (c = 1), this[t + o] = (e / a >> 0) - c & 255;
              return t + n;
            };
            m.prototype.writeInt8 = function(e, t, n) {
              return e = +e, t = t >>> 0, n || V(this, e, t, 1, 127, -128), e < 0 && (e = 255 + e + 1), this[t] = e & 255, t + 1;
            };
            m.prototype.writeInt16LE = function(e, t, n) {
              return e = +e, t = t >>> 0, n || V(this, e, t, 2, 32767, -32768), this[t] = e & 255, this[t + 1] = e >>> 8, t + 2;
            };
            m.prototype.writeInt16BE = function(e, t, n) {
              return e = +e, t = t >>> 0, n || V(this, e, t, 2, 32767, -32768), this[t] = e >>> 8, this[t + 1] = e & 255, t + 2;
            };
            m.prototype.writeInt32LE = function(e, t, n) {
              return e = +e, t = t >>> 0, n || V(this, e, t, 4, 2147483647, -2147483648), this[t] = e & 255, this[t + 1] = e >>> 8, this[t + 2] = e >>> 16, this[t + 3] = e >>> 24, t + 4;
            };
            m.prototype.writeInt32BE = function(e, t, n) {
              return e = +e, t = t >>> 0, n || V(this, e, t, 4, 2147483647, -2147483648), e < 0 && (e = 4294967295 + e + 1), this[t] = e >>> 24, this[t + 1] = e >>> 16, this[t + 2] = e >>> 8, this[t + 3] = e & 255, t + 4;
            };
            m.prototype.writeBigInt64LE = pe(function(e, t = 0) {
              return Br(this, e, t, -BigInt("0x8000000000000000"), BigInt("0x7fffffffffffffff"));
            });
            m.prototype.writeBigInt64BE = pe(function(e, t = 0) {
              return Ir(this, e, t, -BigInt("0x8000000000000000"), BigInt("0x7fffffffffffffff"));
            });
            function Ar(r, e, t, n, i, o) {
              if (t + n > r.length) throw new RangeError("Index out of range");
              if (t < 0) throw new RangeError("Index out of range");
            }
            function Cr(r, e, t, n, i) {
              return e = +e, t = t >>> 0, i || Ar(r, e, t, 4, 34028234663852886e22, -34028234663852886e22), Ee.write(r, e, t, n, 23, 4), t + 4;
            }
            m.prototype.writeFloatLE = function(e, t, n) {
              return Cr(this, e, t, true, n);
            };
            m.prototype.writeFloatBE = function(e, t, n) {
              return Cr(this, e, t, false, n);
            };
            function Sr(r, e, t, n, i) {
              return e = +e, t = t >>> 0, i || Ar(r, e, t, 8, 17976931348623157e292, -17976931348623157e292), Ee.write(r, e, t, n, 52, 8), t + 8;
            }
            m.prototype.writeDoubleLE = function(e, t, n) {
              return Sr(this, e, t, true, n);
            };
            m.prototype.writeDoubleBE = function(e, t, n) {
              return Sr(this, e, t, false, n);
            };
            m.prototype.copy = function(e, t, n, i) {
              if (!m.isBuffer(e)) throw new TypeError("argument should be a Buffer");
              if (n || (n = 0), !i && i !== 0 && (i = this.length), t >= e.length && (t = e.length), t || (t = 0), i > 0 && i < n && (i = n), i === n || e.length === 0 || this.length === 0) return 0;
              if (t < 0) throw new RangeError("targetStart out of bounds");
              if (n < 0 || n >= this.length) throw new RangeError("Index out of range");
              if (i < 0) throw new RangeError("sourceEnd out of bounds");
              i > this.length && (i = this.length), e.length - t < i - n && (i = e.length - t + n);
              let o = i - n;
              return this === e && typeof Uint8Array.prototype.copyWithin == "function" ? this.copyWithin(t, n, i) : Uint8Array.prototype.set.call(e, this.subarray(n, i), t), o;
            };
            m.prototype.fill = function(e, t, n, i) {
              if (typeof e == "string") {
                if (typeof t == "string" ? (i = t, t = 0, n = this.length) : typeof n == "string" && (i = n, n = this.length), i !== void 0 && typeof i != "string") throw new TypeError("encoding must be a string");
                if (typeof i == "string" && !m.isEncoding(i)) throw new TypeError("Unknown encoding: " + i);
                if (e.length === 1) {
                  let a = e.charCodeAt(0);
                  (i === "utf8" && a < 128 || i === "latin1") && (e = a);
                }
              } else typeof e == "number" ? e = e & 255 : typeof e == "boolean" && (e = Number(e));
              if (t < 0 || this.length < t || this.length < n) throw new RangeError("Out of range index");
              if (n <= t) return this;
              t = t >>> 0, n = n === void 0 ? this.length : n >>> 0, e || (e = 0);
              let o;
              if (typeof e == "number") for (o = t; o < n; ++o) this[o] = e;
              else {
                let a = m.isBuffer(e) ? e : m.from(e, i), c = a.length;
                if (c === 0) throw new TypeError('The value "' + e + '" is invalid for argument "value"');
                for (o = 0; o < n - t; ++o) this[o + t] = a[o % c];
              }
              return this;
            };
            var _e = {};
            function St(r, e, t) {
              _e[r] = class extends t {
                constructor() {
                  super(), Object.defineProperty(this, "message", { value: e.apply(this, arguments), writable: true, configurable: true }), this.name = `${this.name} [${r}]`, this.stack, delete this.name;
                }
                get code() {
                  return r;
                }
                set code(i) {
                  Object.defineProperty(this, "code", { configurable: true, enumerable: true, value: i, writable: true });
                }
                toString() {
                  return `${this.name} [${r}]: ${this.message}`;
                }
              };
            }
            St("ERR_BUFFER_OUT_OF_BOUNDS", function(r) {
              return r ? `${r} is outside of buffer bounds` : "Attempt to access memory outside buffer bounds";
            }, RangeError);
            St("ERR_INVALID_ARG_TYPE", function(r, e) {
              return `The "${r}" argument must be of type number. Received type ${typeof e}`;
            }, TypeError);
            St("ERR_OUT_OF_RANGE", function(r, e, t) {
              let n = `The value of "${r}" is out of range.`, i = t;
              return Number.isInteger(t) && Math.abs(t) > 2 ** 32 ? i = mr(String(t)) : typeof t == "bigint" && (i = String(t), (t > BigInt(2) ** BigInt(32) || t < -(BigInt(2) ** BigInt(32))) && (i = mr(i)), i += "n"), n += ` It must be ${e}. Received ${i}`, n;
            }, RangeError);
            function mr(r) {
              let e = "", t = r.length, n = r[0] === "-" ? 1 : 0;
              for (; t >= n + 4; t -= 3) e = `_${r.slice(t - 3, t)}${e}`;
              return `${r.slice(0, t)}${e}`;
            }
            function vi(r, e, t) {
              Be(e, "offset"), (r[e] === void 0 || r[e + t] === void 0) && Le(e, r.length - (t + 1));
            }
            function Ur(r, e, t, n, i, o) {
              if (r > t || r < e) {
                let a = typeof e == "bigint" ? "n" : "", c;
                throw o > 3 ? e === 0 || e === BigInt(0) ? c = `>= 0${a} and < 2${a} ** ${(o + 1) * 8}${a}` : c = `>= -(2${a} ** ${(o + 1) * 8 - 1}${a}) and < 2 ** ${(o + 1) * 8 - 1}${a}` : c = `>= ${e}${a} and <= ${t}${a}`, new _e.ERR_OUT_OF_RANGE("value", c, r);
              }
              vi(n, i, o);
            }
            function Be(r, e) {
              if (typeof r != "number") throw new _e.ERR_INVALID_ARG_TYPE(e, "number", r);
            }
            function Le(r, e, t) {
              throw Math.floor(r) !== r ? (Be(r, t), new _e.ERR_OUT_OF_RANGE(t || "offset", "an integer", r)) : e < 0 ? new _e.ERR_BUFFER_OUT_OF_BOUNDS() : new _e.ERR_OUT_OF_RANGE(t || "offset", `>= ${t ? 1 : 0} and <= ${e}`, r);
            }
            var wi = /[^+/0-9A-Za-z-_]/g;
            function _i(r) {
              if (r = r.split("=")[0], r = r.trim().replace(wi, ""), r.length < 2) return "";
              for (; r.length % 4 !== 0; ) r = r + "=";
              return r;
            }
            function It(r, e) {
              e = e || 1 / 0;
              let t, n = r.length, i = null, o = [];
              for (let a = 0; a < n; ++a) {
                if (t = r.charCodeAt(a), t > 55295 && t < 57344) {
                  if (!i) {
                    if (t > 56319) {
                      (e -= 3) > -1 && o.push(239, 191, 189);
                      continue;
                    } else if (a + 1 === n) {
                      (e -= 3) > -1 && o.push(239, 191, 189);
                      continue;
                    }
                    i = t;
                    continue;
                  }
                  if (t < 56320) {
                    (e -= 3) > -1 && o.push(239, 191, 189), i = t;
                    continue;
                  }
                  t = (i - 55296 << 10 | t - 56320) + 65536;
                } else i && (e -= 3) > -1 && o.push(239, 191, 189);
                if (i = null, t < 128) {
                  if ((e -= 1) < 0) break;
                  o.push(t);
                } else if (t < 2048) {
                  if ((e -= 2) < 0) break;
                  o.push(t >> 6 | 192, t & 63 | 128);
                } else if (t < 65536) {
                  if ((e -= 3) < 0) break;
                  o.push(t >> 12 | 224, t >> 6 & 63 | 128, t & 63 | 128);
                } else if (t < 1114112) {
                  if ((e -= 4) < 0) break;
                  o.push(t >> 18 | 240, t >> 12 & 63 | 128, t >> 6 & 63 | 128, t & 63 | 128);
                } else throw new Error("Invalid code point");
              }
              return o;
            }
            function Ei(r) {
              let e = [];
              for (let t = 0; t < r.length; ++t) e.push(r.charCodeAt(t) & 255);
              return e;
            }
            function Bi(r, e) {
              let t, n, i, o = [];
              for (let a = 0; a < r.length && !((e -= 2) < 0); ++a) t = r.charCodeAt(a), n = t >> 8, i = t % 256, o.push(i), o.push(n);
              return o;
            }
            function Fr(r) {
              return _t.toByteArray(_i(r));
            }
            function We(r, e, t, n) {
              let i;
              for (i = 0; i < n && !(i + t >= e.length || i >= r.length); ++i) e[i + t] = r[i];
              return i;
            }
            function ce(r, e) {
              return r instanceof e || r != null && r.constructor != null && r.constructor.name != null && r.constructor.name === e.name;
            }
            function Ut(r) {
              return r !== r;
            }
            var Ii = (function() {
              let r = "0123456789abcdef", e = new Array(256);
              for (let t = 0; t < 16; ++t) {
                let n = t * 16;
                for (let i = 0; i < 16; ++i) e[n + i] = r[t] + r[i];
              }
              return e;
            })();
            function pe(r) {
              return typeof BigInt > "u" ? Ai : r;
            }
            function Ai() {
              throw new Error("BigInt not supported");
            }
          });
          var kr = z(() => {
          });
          var X = z((Ke, Rr) => {
            (function(r, e) {
              typeof Ke == "object" ? Rr.exports = Ke = e() : typeof define == "function" && define.amd ? define([], e) : r.CryptoJS = e();
            })(Ke, function() {
              var r = r || (function(e, t) {
                var n;
                if (typeof window < "u" && window.crypto && (n = window.crypto), typeof self < "u" && self.crypto && (n = self.crypto), typeof globalThis < "u" && globalThis.crypto && (n = globalThis.crypto), !n && typeof window < "u" && window.msCrypto && (n = window.msCrypto), !n && typeof global < "u" && global.crypto && (n = global.crypto), !n && typeof Xt == "function") try {
                  n = kr();
                } catch (e2) {
                }
                var i = function() {
                  if (n) {
                    if (typeof n.getRandomValues == "function") try {
                      return n.getRandomValues(new Uint32Array(1))[0];
                    } catch (e2) {
                    }
                    if (typeof n.randomBytes == "function") try {
                      return n.randomBytes(4).readInt32LE();
                    } catch (e2) {
                    }
                  }
                  throw new Error("Native crypto module could not be used to get secure random number.");
                }, o = Object.create || /* @__PURE__ */ (function() {
                  function l() {
                  }
                  return function(p) {
                    var g;
                    return l.prototype = p, g = new l(), l.prototype = null, g;
                  };
                })(), a = {}, c = a.lib = {}, s = c.Base = /* @__PURE__ */ (function() {
                  return { extend: function(l) {
                    var p = o(this);
                    return l && p.mixIn(l), (!p.hasOwnProperty("init") || this.init === p.init) && (p.init = function() {
                      p.$super.init.apply(this, arguments);
                    }), p.init.prototype = p, p.$super = this, p;
                  }, create: function() {
                    var l = this.extend();
                    return l.init.apply(l, arguments), l;
                  }, init: function() {
                  }, mixIn: function(l) {
                    for (var p in l) l.hasOwnProperty(p) && (this[p] = l[p]);
                    l.hasOwnProperty("toString") && (this.toString = l.toString);
                  }, clone: function() {
                    return this.init.prototype.extend(this);
                  } };
                })(), u = c.WordArray = s.extend({ init: function(l, p) {
                  l = this.words = l || [], p != t ? this.sigBytes = p : this.sigBytes = l.length * 4;
                }, toString: function(l) {
                  return (l || h).stringify(this);
                }, concat: function(l) {
                  var p = this.words, g = l.words, v = this.sigBytes, U = l.sigBytes;
                  if (this.clamp(), v % 4) for (var R = 0; R < U; R++) {
                    var L = g[R >>> 2] >>> 24 - R % 4 * 8 & 255;
                    p[v + R >>> 2] |= L << 24 - (v + R) % 4 * 8;
                  }
                  else for (var N = 0; N < U; N += 4) p[v + N >>> 2] = g[N >>> 2];
                  return this.sigBytes += U, this;
                }, clamp: function() {
                  var l = this.words, p = this.sigBytes;
                  l[p >>> 2] &= 4294967295 << 32 - p % 4 * 8, l.length = e.ceil(p / 4);
                }, clone: function() {
                  var l = s.clone.call(this);
                  return l.words = this.words.slice(0), l;
                }, random: function(l) {
                  for (var p = [], g = 0; g < l; g += 4) p.push(i());
                  return new u.init(p, l);
                } }), f = a.enc = {}, h = f.Hex = { stringify: function(l) {
                  for (var p = l.words, g = l.sigBytes, v = [], U = 0; U < g; U++) {
                    var R = p[U >>> 2] >>> 24 - U % 4 * 8 & 255;
                    v.push((R >>> 4).toString(16)), v.push((R & 15).toString(16));
                  }
                  return v.join("");
                }, parse: function(l) {
                  for (var p = l.length, g = [], v = 0; v < p; v += 2) g[v >>> 3] |= parseInt(l.substr(v, 2), 16) << 24 - v % 8 * 4;
                  return new u.init(g, p / 2);
                } }, d = f.Latin1 = { stringify: function(l) {
                  for (var p = l.words, g = l.sigBytes, v = [], U = 0; U < g; U++) {
                    var R = p[U >>> 2] >>> 24 - U % 4 * 8 & 255;
                    v.push(String.fromCharCode(R));
                  }
                  return v.join("");
                }, parse: function(l) {
                  for (var p = l.length, g = [], v = 0; v < p; v++) g[v >>> 2] |= (l.charCodeAt(v) & 255) << 24 - v % 4 * 8;
                  return new u.init(g, p);
                } }, x = f.Utf8 = { stringify: function(l) {
                  try {
                    return decodeURIComponent(escape(d.stringify(l)));
                  } catch (e2) {
                    throw new Error("Malformed UTF-8 data");
                  }
                }, parse: function(l) {
                  return d.parse(unescape(encodeURIComponent(l)));
                } }, y = c.BufferedBlockAlgorithm = s.extend({ reset: function() {
                  this._data = new u.init(), this._nDataBytes = 0;
                }, _append: function(l) {
                  typeof l == "string" && (l = x.parse(l)), this._data.concat(l), this._nDataBytes += l.sigBytes;
                }, _process: function(l) {
                  var p, g = this._data, v = g.words, U = g.sigBytes, R = this.blockSize, L = R * 4, N = U / L;
                  l ? N = e.ceil(N) : N = e.max((N | 0) - this._minBufferSize, 0);
                  var k = N * R, T = e.min(k * 4, U);
                  if (k) {
                    for (var b = 0; b < k; b += R) this._doProcessBlock(v, b);
                    p = v.splice(0, k), g.sigBytes -= T;
                  }
                  return new u.init(p, T);
                }, clone: function() {
                  var l = s.clone.call(this);
                  return l._data = this._data.clone(), l;
                }, _minBufferSize: 0 }), I = c.Hasher = y.extend({ cfg: s.extend(), init: function(l) {
                  this.cfg = this.cfg.extend(l), this.reset();
                }, reset: function() {
                  y.reset.call(this), this._doReset();
                }, update: function(l) {
                  return this._append(l), this._process(), this;
                }, finalize: function(l) {
                  l && this._append(l);
                  var p = this._doFinalize();
                  return p;
                }, blockSize: 512 / 32, _createHelper: function(l) {
                  return function(p, g) {
                    return new l.init(g).finalize(p);
                  };
                }, _createHmacHelper: function(l) {
                  return function(p, g) {
                    return new F.HMAC.init(l, g).finalize(p);
                  };
                } }), F = a.algo = {};
                return a;
              })(Math);
              return r;
            });
          });
          var Ft = z((Ge, Dr) => {
            (function(r, e) {
              typeof Ge == "object" ? Dr.exports = Ge = e(X()) : typeof define == "function" && define.amd ? define(["./core"], e) : e(r.CryptoJS);
            })(Ge, function(r) {
              return (function(e) {
                var t = r, n = t.lib, i = n.WordArray, o = n.Hasher, a = t.algo, c = [];
                (function() {
                  for (var x = 0; x < 64; x++) c[x] = e.abs(e.sin(x + 1)) * 4294967296 | 0;
                })();
                var s = a.MD5 = o.extend({ _doReset: function() {
                  this._hash = new i.init([1732584193, 4023233417, 2562383102, 271733878]);
                }, _doProcessBlock: function(x, y) {
                  for (var I = 0; I < 16; I++) {
                    var F = y + I, l = x[F];
                    x[F] = (l << 8 | l >>> 24) & 16711935 | (l << 24 | l >>> 8) & 4278255360;
                  }
                  var p = this._hash.words, g = x[y + 0], v = x[y + 1], U = x[y + 2], R = x[y + 3], L = x[y + 4], N = x[y + 5], k = x[y + 6], T = x[y + 7], b = x[y + 8], A = x[y + 9], D = x[y + 10], w = x[y + 11], H = x[y + 12], O = x[y + 13], P = x[y + 14], q = x[y + 15], _ = p[0], E = p[1], C = p[2], B = p[3];
                  _ = u(_, E, C, B, g, 7, c[0]), B = u(B, _, E, C, v, 12, c[1]), C = u(C, B, _, E, U, 17, c[2]), E = u(E, C, B, _, R, 22, c[3]), _ = u(_, E, C, B, L, 7, c[4]), B = u(B, _, E, C, N, 12, c[5]), C = u(C, B, _, E, k, 17, c[6]), E = u(E, C, B, _, T, 22, c[7]), _ = u(_, E, C, B, b, 7, c[8]), B = u(B, _, E, C, A, 12, c[9]), C = u(C, B, _, E, D, 17, c[10]), E = u(E, C, B, _, w, 22, c[11]), _ = u(_, E, C, B, H, 7, c[12]), B = u(B, _, E, C, O, 12, c[13]), C = u(C, B, _, E, P, 17, c[14]), E = u(E, C, B, _, q, 22, c[15]), _ = f(_, E, C, B, v, 5, c[16]), B = f(B, _, E, C, k, 9, c[17]), C = f(C, B, _, E, w, 14, c[18]), E = f(E, C, B, _, g, 20, c[19]), _ = f(_, E, C, B, N, 5, c[20]), B = f(B, _, E, C, D, 9, c[21]), C = f(C, B, _, E, q, 14, c[22]), E = f(E, C, B, _, L, 20, c[23]), _ = f(_, E, C, B, A, 5, c[24]), B = f(B, _, E, C, P, 9, c[25]), C = f(C, B, _, E, R, 14, c[26]), E = f(E, C, B, _, b, 20, c[27]), _ = f(_, E, C, B, O, 5, c[28]), B = f(B, _, E, C, U, 9, c[29]), C = f(C, B, _, E, T, 14, c[30]), E = f(E, C, B, _, H, 20, c[31]), _ = h(_, E, C, B, N, 4, c[32]), B = h(B, _, E, C, b, 11, c[33]), C = h(C, B, _, E, w, 16, c[34]), E = h(E, C, B, _, P, 23, c[35]), _ = h(_, E, C, B, v, 4, c[36]), B = h(B, _, E, C, L, 11, c[37]), C = h(C, B, _, E, T, 16, c[38]), E = h(E, C, B, _, D, 23, c[39]), _ = h(_, E, C, B, O, 4, c[40]), B = h(B, _, E, C, g, 11, c[41]), C = h(C, B, _, E, R, 16, c[42]), E = h(E, C, B, _, k, 23, c[43]), _ = h(_, E, C, B, A, 4, c[44]), B = h(B, _, E, C, H, 11, c[45]), C = h(C, B, _, E, q, 16, c[46]), E = h(E, C, B, _, U, 23, c[47]), _ = d(_, E, C, B, g, 6, c[48]), B = d(B, _, E, C, T, 10, c[49]), C = d(C, B, _, E, P, 15, c[50]), E = d(E, C, B, _, N, 21, c[51]), _ = d(_, E, C, B, H, 6, c[52]), B = d(B, _, E, C, R, 10, c[53]), C = d(C, B, _, E, D, 15, c[54]), E = d(E, C, B, _, v, 21, c[55]), _ = d(_, E, C, B, b, 6, c[56]), B = d(B, _, E, C, q, 10, c[57]), C = d(C, B, _, E, k, 15, c[58]), E = d(E, C, B, _, O, 21, c[59]), _ = d(_, E, C, B, L, 6, c[60]), B = d(B, _, E, C, w, 10, c[61]), C = d(C, B, _, E, U, 15, c[62]), E = d(E, C, B, _, A, 21, c[63]), p[0] = p[0] + _ | 0, p[1] = p[1] + E | 0, p[2] = p[2] + C | 0, p[3] = p[3] + B | 0;
                }, _doFinalize: function() {
                  var x = this._data, y = x.words, I = this._nDataBytes * 8, F = x.sigBytes * 8;
                  y[F >>> 5] |= 128 << 24 - F % 32;
                  var l = e.floor(I / 4294967296), p = I;
                  y[(F + 64 >>> 9 << 4) + 15] = (l << 8 | l >>> 24) & 16711935 | (l << 24 | l >>> 8) & 4278255360, y[(F + 64 >>> 9 << 4) + 14] = (p << 8 | p >>> 24) & 16711935 | (p << 24 | p >>> 8) & 4278255360, x.sigBytes = (y.length + 1) * 4, this._process();
                  for (var g = this._hash, v = g.words, U = 0; U < 4; U++) {
                    var R = v[U];
                    v[U] = (R << 8 | R >>> 24) & 16711935 | (R << 24 | R >>> 8) & 4278255360;
                  }
                  return g;
                }, clone: function() {
                  var x = o.clone.call(this);
                  return x._hash = this._hash.clone(), x;
                } });
                function u(x, y, I, F, l, p, g) {
                  var v = x + (y & I | ~y & F) + l + g;
                  return (v << p | v >>> 32 - p) + y;
                }
                function f(x, y, I, F, l, p, g) {
                  var v = x + (y & F | I & ~F) + l + g;
                  return (v << p | v >>> 32 - p) + y;
                }
                function h(x, y, I, F, l, p, g) {
                  var v = x + (y ^ I ^ F) + l + g;
                  return (v << p | v >>> 32 - p) + y;
                }
                function d(x, y, I, F, l, p, g) {
                  var v = x + (I ^ (y | ~F)) + l + g;
                  return (v << p | v >>> 32 - p) + y;
                }
                t.MD5 = o._createHelper(s), t.HmacMD5 = o._createHmacHelper(s);
              })(Math), r.MD5;
            });
          });
          var Tr = z((Ye, Nr) => {
            (function(r, e) {
              typeof Ye == "object" ? Nr.exports = Ye = e(X()) : typeof define == "function" && define.amd ? define(["./core"], e) : e(r.CryptoJS);
            })(Ye, function(r) {
              return (function(e) {
                var t = r, n = t.lib, i = n.Base, o = n.WordArray, a = t.x64 = {}, c = a.Word = i.extend({ init: function(u, f) {
                  this.high = u, this.low = f;
                } }), s = a.WordArray = i.extend({ init: function(u, f) {
                  u = this.words = u || [], f != e ? this.sigBytes = f : this.sigBytes = u.length * 8;
                }, toX32: function() {
                  for (var u = this.words, f = u.length, h = [], d = 0; d < f; d++) {
                    var x = u[d];
                    h.push(x.high), h.push(x.low);
                  }
                  return o.create(h, this.sigBytes);
                }, clone: function() {
                  for (var u = i.clone.call(this), f = u.words = this.words.slice(0), h = f.length, d = 0; d < h; d++) f[d] = f[d].clone();
                  return u;
                } });
              })(), r;
            });
          });
          var Hr = z((Xe, Lr) => {
            (function(r, e, t) {
              typeof Xe == "object" ? Lr.exports = Xe = e(X(), Tr()) : typeof define == "function" && define.amd ? define(["./core", "./x64-core"], e) : e(r.CryptoJS);
            })(Xe, function(r) {
              return (function() {
                var e = r, t = e.lib, n = t.Hasher, i = e.x64, o = i.Word, a = i.WordArray, c = e.algo;
                function s() {
                  return o.create.apply(o, arguments);
                }
                var u = [s(1116352408, 3609767458), s(1899447441, 602891725), s(3049323471, 3964484399), s(3921009573, 2173295548), s(961987163, 4081628472), s(1508970993, 3053834265), s(2453635748, 2937671579), s(2870763221, 3664609560), s(3624381080, 2734883394), s(310598401, 1164996542), s(607225278, 1323610764), s(1426881987, 3590304994), s(1925078388, 4068182383), s(2162078206, 991336113), s(2614888103, 633803317), s(3248222580, 3479774868), s(3835390401, 2666613458), s(4022224774, 944711139), s(264347078, 2341262773), s(604807628, 2007800933), s(770255983, 1495990901), s(1249150122, 1856431235), s(1555081692, 3175218132), s(1996064986, 2198950837), s(2554220882, 3999719339), s(2821834349, 766784016), s(2952996808, 2566594879), s(3210313671, 3203337956), s(3336571891, 1034457026), s(3584528711, 2466948901), s(113926993, 3758326383), s(338241895, 168717936), s(666307205, 1188179964), s(773529912, 1546045734), s(1294757372, 1522805485), s(1396182291, 2643833823), s(1695183700, 2343527390), s(1986661051, 1014477480), s(2177026350, 1206759142), s(2456956037, 344077627), s(2730485921, 1290863460), s(2820302411, 3158454273), s(3259730800, 3505952657), s(3345764771, 106217008), s(3516065817, 3606008344), s(3600352804, 1432725776), s(4094571909, 1467031594), s(275423344, 851169720), s(430227734, 3100823752), s(506948616, 1363258195), s(659060556, 3750685593), s(883997877, 3785050280), s(958139571, 3318307427), s(1322822218, 3812723403), s(1537002063, 2003034995), s(1747873779, 3602036899), s(1955562222, 1575990012), s(2024104815, 1125592928), s(2227730452, 2716904306), s(2361852424, 442776044), s(2428436474, 593698344), s(2756734187, 3733110249), s(3204031479, 2999351573), s(3329325298, 3815920427), s(3391569614, 3928383900), s(3515267271, 566280711), s(3940187606, 3454069534), s(4118630271, 4000239992), s(116418474, 1914138554), s(174292421, 2731055270), s(289380356, 3203993006), s(460393269, 320620315), s(685471733, 587496836), s(852142971, 1086792851), s(1017036298, 365543100), s(1126000580, 2618297676), s(1288033470, 3409855158), s(1501505948, 4234509866), s(1607167915, 987167468), s(1816402316, 1246189591)], f = [];
                (function() {
                  for (var d = 0; d < 80; d++) f[d] = s();
                })();
                var h = c.SHA512 = n.extend({ _doReset: function() {
                  this._hash = new a.init([new o.init(1779033703, 4089235720), new o.init(3144134277, 2227873595), new o.init(1013904242, 4271175723), new o.init(2773480762, 1595750129), new o.init(1359893119, 2917565137), new o.init(2600822924, 725511199), new o.init(528734635, 4215389547), new o.init(1541459225, 327033209)]);
                }, _doProcessBlock: function(d, x) {
                  for (var y = this._hash.words, I = y[0], F = y[1], l = y[2], p = y[3], g = y[4], v = y[5], U = y[6], R = y[7], L = I.high, N = I.low, k = F.high, T = F.low, b = l.high, A = l.low, D = p.high, w = p.low, H = g.high, O = g.low, P = v.high, q = v.low, _ = U.high, E = U.low, C = R.high, B = R.low, Q = L, $ = N, Se = k, me = T, Ue = b, be = A, xt = D, Fe = w, ee = H, W = O, Me = P, ke = q, ze = _, Re = E, yt = C, De = B, te = 0; te < 80; te++) {
                    var G, le, qe = f[te];
                    if (te < 16) le = qe.high = d[x + te * 2] | 0, G = qe.low = d[x + te * 2 + 1] | 0;
                    else {
                      var Pt = f[te - 15], ve = Pt.high, Ne = Pt.low, In = (ve >>> 1 | Ne << 31) ^ (ve >>> 8 | Ne << 24) ^ ve >>> 7, Mt = (Ne >>> 1 | ve << 31) ^ (Ne >>> 8 | ve << 24) ^ (Ne >>> 7 | ve << 25), zt = f[te - 2], we = zt.high, Te = zt.low, An = (we >>> 19 | Te << 13) ^ (we << 3 | Te >>> 29) ^ we >>> 6, qt = (Te >>> 19 | we << 13) ^ (Te << 3 | we >>> 29) ^ (Te >>> 6 | we << 26), jt = f[te - 7], Cn = jt.high, Sn = jt.low, Vt = f[te - 16], Un = Vt.high, $t = Vt.low;
                      G = Mt + Sn, le = In + Cn + (G >>> 0 < Mt >>> 0 ? 1 : 0), G = G + qt, le = le + An + (G >>> 0 < qt >>> 0 ? 1 : 0), G = G + $t, le = le + Un + (G >>> 0 < $t >>> 0 ? 1 : 0), qe.high = le, qe.low = G;
                    }
                    var Fn = ee & Me ^ ~ee & ze, Wt = W & ke ^ ~W & Re, kn = Q & Se ^ Q & Ue ^ Se & Ue, Rn = $ & me ^ $ & be ^ me & be, Dn = (Q >>> 28 | $ << 4) ^ (Q << 30 | $ >>> 2) ^ (Q << 25 | $ >>> 7), Jt = ($ >>> 28 | Q << 4) ^ ($ << 30 | Q >>> 2) ^ ($ << 25 | Q >>> 7), Nn = (ee >>> 14 | W << 18) ^ (ee >>> 18 | W << 14) ^ (ee << 23 | W >>> 9), Tn = (W >>> 14 | ee << 18) ^ (W >>> 18 | ee << 14) ^ (W << 23 | ee >>> 9), Kt = u[te], Ln = Kt.high, Gt = Kt.low, J = De + Tn, de = yt + Nn + (J >>> 0 < De >>> 0 ? 1 : 0), J = J + Wt, de = de + Fn + (J >>> 0 < Wt >>> 0 ? 1 : 0), J = J + Gt, de = de + Ln + (J >>> 0 < Gt >>> 0 ? 1 : 0), J = J + G, de = de + le + (J >>> 0 < G >>> 0 ? 1 : 0), Yt = Jt + Rn, Hn = Dn + kn + (Yt >>> 0 < Jt >>> 0 ? 1 : 0);
                    yt = ze, De = Re, ze = Me, Re = ke, Me = ee, ke = W, W = Fe + J | 0, ee = xt + de + (W >>> 0 < Fe >>> 0 ? 1 : 0) | 0, xt = Ue, Fe = be, Ue = Se, be = me, Se = Q, me = $, $ = J + Yt | 0, Q = de + Hn + ($ >>> 0 < J >>> 0 ? 1 : 0) | 0;
                  }
                  N = I.low = N + $, I.high = L + Q + (N >>> 0 < $ >>> 0 ? 1 : 0), T = F.low = T + me, F.high = k + Se + (T >>> 0 < me >>> 0 ? 1 : 0), A = l.low = A + be, l.high = b + Ue + (A >>> 0 < be >>> 0 ? 1 : 0), w = p.low = w + Fe, p.high = D + xt + (w >>> 0 < Fe >>> 0 ? 1 : 0), O = g.low = O + W, g.high = H + ee + (O >>> 0 < W >>> 0 ? 1 : 0), q = v.low = q + ke, v.high = P + Me + (q >>> 0 < ke >>> 0 ? 1 : 0), E = U.low = E + Re, U.high = _ + ze + (E >>> 0 < Re >>> 0 ? 1 : 0), B = R.low = B + De, R.high = C + yt + (B >>> 0 < De >>> 0 ? 1 : 0);
                }, _doFinalize: function() {
                  var d = this._data, x = d.words, y = this._nDataBytes * 8, I = d.sigBytes * 8;
                  x[I >>> 5] |= 128 << 24 - I % 32, x[(I + 128 >>> 10 << 5) + 30] = Math.floor(y / 4294967296), x[(I + 128 >>> 10 << 5) + 31] = y, d.sigBytes = x.length * 4, this._process();
                  var F = this._hash.toX32();
                  return F;
                }, clone: function() {
                  var d = n.clone.call(this);
                  return d._hash = this._hash.clone(), d;
                }, blockSize: 1024 / 32 });
                e.SHA512 = n._createHelper(h), e.HmacSHA512 = n._createHmacHelper(h);
              })(), r.SHA512;
            });
          });
          var Pr = z((Ze, Or) => {
            (function(r, e) {
              typeof Ze == "object" ? Or.exports = Ze = e(X()) : typeof define == "function" && define.amd ? define(["./core"], e) : e(r.CryptoJS);
            })(Ze, function(r) {
              return (function() {
                var e = r, t = e.lib, n = t.WordArray, i = e.enc, o = i.Base64 = { stringify: function(c) {
                  var s = c.words, u = c.sigBytes, f = this._map;
                  c.clamp();
                  for (var h = [], d = 0; d < u; d += 3) for (var x = s[d >>> 2] >>> 24 - d % 4 * 8 & 255, y = s[d + 1 >>> 2] >>> 24 - (d + 1) % 4 * 8 & 255, I = s[d + 2 >>> 2] >>> 24 - (d + 2) % 4 * 8 & 255, F = x << 16 | y << 8 | I, l = 0; l < 4 && d + l * 0.75 < u; l++) h.push(f.charAt(F >>> 6 * (3 - l) & 63));
                  var p = f.charAt(64);
                  if (p) for (; h.length % 4; ) h.push(p);
                  return h.join("");
                }, parse: function(c) {
                  var s = c.length, u = this._map, f = this._reverseMap;
                  if (!f) {
                    f = this._reverseMap = [];
                    for (var h = 0; h < u.length; h++) f[u.charCodeAt(h)] = h;
                  }
                  var d = u.charAt(64);
                  if (d) {
                    var x = c.indexOf(d);
                    x !== -1 && (s = x);
                  }
                  return a(c, s, f);
                }, _map: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=" };
                function a(c, s, u) {
                  for (var f = [], h = 0, d = 0; d < s; d++) if (d % 4) {
                    var x = u[c.charCodeAt(d - 1)] << d % 4 * 2, y = u[c.charCodeAt(d)] >>> 6 - d % 4 * 2, I = x | y;
                    f[h >>> 2] |= I << 24 - h % 4 * 8, h++;
                  }
                  return n.create(f, h);
                }
              })(), r.enc.Base64;
            });
          });
          var zr = z((Qe, Mr) => {
            (function(r, e) {
              typeof Qe == "object" ? Mr.exports = Qe = e(X()) : typeof define == "function" && define.amd ? define(["./core"], e) : e(r.CryptoJS);
            })(Qe, function(r) {
              return (function() {
                var e = r, t = e.lib, n = t.WordArray, i = t.Hasher, o = e.algo, a = [], c = o.SHA1 = i.extend({ _doReset: function() {
                  this._hash = new n.init([1732584193, 4023233417, 2562383102, 271733878, 3285377520]);
                }, _doProcessBlock: function(s, u) {
                  for (var f = this._hash.words, h = f[0], d = f[1], x = f[2], y = f[3], I = f[4], F = 0; F < 80; F++) {
                    if (F < 16) a[F] = s[u + F] | 0;
                    else {
                      var l = a[F - 3] ^ a[F - 8] ^ a[F - 14] ^ a[F - 16];
                      a[F] = l << 1 | l >>> 31;
                    }
                    var p = (h << 5 | h >>> 27) + I + a[F];
                    F < 20 ? p += (d & x | ~d & y) + 1518500249 : F < 40 ? p += (d ^ x ^ y) + 1859775393 : F < 60 ? p += (d & x | d & y | x & y) - 1894007588 : p += (d ^ x ^ y) - 899497514, I = y, y = x, x = d << 30 | d >>> 2, d = h, h = p;
                  }
                  f[0] = f[0] + h | 0, f[1] = f[1] + d | 0, f[2] = f[2] + x | 0, f[3] = f[3] + y | 0, f[4] = f[4] + I | 0;
                }, _doFinalize: function() {
                  var s = this._data, u = s.words, f = this._nDataBytes * 8, h = s.sigBytes * 8;
                  return u[h >>> 5] |= 128 << 24 - h % 32, u[(h + 64 >>> 9 << 4) + 14] = Math.floor(f / 4294967296), u[(h + 64 >>> 9 << 4) + 15] = f, s.sigBytes = u.length * 4, this._process(), this._hash;
                }, clone: function() {
                  var s = i.clone.call(this);
                  return s._hash = this._hash.clone(), s;
                } });
                e.SHA1 = i._createHelper(c), e.HmacSHA1 = i._createHmacHelper(c);
              })(), r.SHA1;
            });
          });
          var jr = z((et, qr) => {
            (function(r, e) {
              typeof et == "object" ? qr.exports = et = e(X()) : typeof define == "function" && define.amd ? define(["./core"], e) : e(r.CryptoJS);
            })(et, function(r) {
              (function() {
                var e = r, t = e.lib, n = t.Base, i = e.enc, o = i.Utf8, a = e.algo, c = a.HMAC = n.extend({ init: function(s, u) {
                  s = this._hasher = new s.init(), typeof u == "string" && (u = o.parse(u));
                  var f = s.blockSize, h = f * 4;
                  u.sigBytes > h && (u = s.finalize(u)), u.clamp();
                  for (var d = this._oKey = u.clone(), x = this._iKey = u.clone(), y = d.words, I = x.words, F = 0; F < f; F++) y[F] ^= 1549556828, I[F] ^= 909522486;
                  d.sigBytes = x.sigBytes = h, this.reset();
                }, reset: function() {
                  var s = this._hasher;
                  s.reset(), s.update(this._iKey);
                }, update: function(s) {
                  return this._hasher.update(s), this;
                }, finalize: function(s) {
                  var u = this._hasher, f = u.finalize(s);
                  u.reset();
                  var h = u.finalize(this._oKey.clone().concat(f));
                  return h;
                } });
              })();
            });
          });
          var kt = z((tt, Vr) => {
            (function(r, e, t) {
              typeof tt == "object" ? Vr.exports = tt = e(X(), zr(), jr()) : typeof define == "function" && define.amd ? define(["./core", "./sha1", "./hmac"], e) : e(r.CryptoJS);
            })(tt, function(r) {
              return (function() {
                var e = r, t = e.lib, n = t.Base, i = t.WordArray, o = e.algo, a = o.MD5, c = o.EvpKDF = n.extend({ cfg: n.extend({ keySize: 128 / 32, hasher: a, iterations: 1 }), init: function(s) {
                  this.cfg = this.cfg.extend(s);
                }, compute: function(s, u) {
                  for (var f, h = this.cfg, d = h.hasher.create(), x = i.create(), y = x.words, I = h.keySize, F = h.iterations; y.length < I; ) {
                    f && d.update(f), f = d.update(s).finalize(u), d.reset();
                    for (var l = 1; l < F; l++) f = d.finalize(f), d.reset();
                    x.concat(f);
                  }
                  return x.sigBytes = I * 4, x;
                } });
                e.EvpKDF = function(s, u, f) {
                  return c.create(f).compute(s, u);
                };
              })(), r.EvpKDF;
            });
          });
          var Rt = z((rt, $r) => {
            (function(r, e, t) {
              typeof rt == "object" ? $r.exports = rt = e(X(), kt()) : typeof define == "function" && define.amd ? define(["./core", "./evpkdf"], e) : e(r.CryptoJS);
            })(rt, function(r) {
              r.lib.Cipher || (function(e) {
                var t = r, n = t.lib, i = n.Base, o = n.WordArray, a = n.BufferedBlockAlgorithm, c = t.enc, s = c.Utf8, u = c.Base64, f = t.algo, h = f.EvpKDF, d = n.Cipher = a.extend({ cfg: i.extend(), createEncryptor: function(b, A) {
                  return this.create(this._ENC_XFORM_MODE, b, A);
                }, createDecryptor: function(b, A) {
                  return this.create(this._DEC_XFORM_MODE, b, A);
                }, init: function(b, A, D) {
                  this.cfg = this.cfg.extend(D), this._xformMode = b, this._key = A, this.reset();
                }, reset: function() {
                  a.reset.call(this), this._doReset();
                }, process: function(b) {
                  return this._append(b), this._process();
                }, finalize: function(b) {
                  b && this._append(b);
                  var A = this._doFinalize();
                  return A;
                }, keySize: 128 / 32, ivSize: 128 / 32, _ENC_XFORM_MODE: 1, _DEC_XFORM_MODE: 2, _createHelper: /* @__PURE__ */ (function() {
                  function b(A) {
                    return typeof A == "string" ? T : L;
                  }
                  return function(A) {
                    return { encrypt: function(D, w, H) {
                      return b(w).encrypt(A, D, w, H);
                    }, decrypt: function(D, w, H) {
                      return b(w).decrypt(A, D, w, H);
                    } };
                  };
                })() }), x = n.StreamCipher = d.extend({ _doFinalize: function() {
                  var b = this._process(true);
                  return b;
                }, blockSize: 1 }), y = t.mode = {}, I = n.BlockCipherMode = i.extend({ createEncryptor: function(b, A) {
                  return this.Encryptor.create(b, A);
                }, createDecryptor: function(b, A) {
                  return this.Decryptor.create(b, A);
                }, init: function(b, A) {
                  this._cipher = b, this._iv = A;
                } }), F = y.CBC = (function() {
                  var b = I.extend();
                  b.Encryptor = b.extend({ processBlock: function(D, w) {
                    var H = this._cipher, O = H.blockSize;
                    A.call(this, D, w, O), H.encryptBlock(D, w), this._prevBlock = D.slice(w, w + O);
                  } }), b.Decryptor = b.extend({ processBlock: function(D, w) {
                    var H = this._cipher, O = H.blockSize, P = D.slice(w, w + O);
                    H.decryptBlock(D, w), A.call(this, D, w, O), this._prevBlock = P;
                  } });
                  function A(D, w, H) {
                    var O, P = this._iv;
                    P ? (O = P, this._iv = e) : O = this._prevBlock;
                    for (var q = 0; q < H; q++) D[w + q] ^= O[q];
                  }
                  return b;
                })(), l = t.pad = {}, p = l.Pkcs7 = { pad: function(b, A) {
                  for (var D = A * 4, w = D - b.sigBytes % D, H = w << 24 | w << 16 | w << 8 | w, O = [], P = 0; P < w; P += 4) O.push(H);
                  var q = o.create(O, w);
                  b.concat(q);
                }, unpad: function(b) {
                  var A = b.words[b.sigBytes - 1 >>> 2] & 255;
                  b.sigBytes -= A;
                } }, g = n.BlockCipher = d.extend({ cfg: d.cfg.extend({ mode: F, padding: p }), reset: function() {
                  var b;
                  d.reset.call(this);
                  var A = this.cfg, D = A.iv, w = A.mode;
                  this._xformMode == this._ENC_XFORM_MODE ? b = w.createEncryptor : (b = w.createDecryptor, this._minBufferSize = 1), this._mode && this._mode.__creator == b ? this._mode.init(this, D && D.words) : (this._mode = b.call(w, this, D && D.words), this._mode.__creator = b);
                }, _doProcessBlock: function(b, A) {
                  this._mode.processBlock(b, A);
                }, _doFinalize: function() {
                  var b, A = this.cfg.padding;
                  return this._xformMode == this._ENC_XFORM_MODE ? (A.pad(this._data, this.blockSize), b = this._process(true)) : (b = this._process(true), A.unpad(b)), b;
                }, blockSize: 128 / 32 }), v = n.CipherParams = i.extend({ init: function(b) {
                  this.mixIn(b);
                }, toString: function(b) {
                  return (b || this.formatter).stringify(this);
                } }), U = t.format = {}, R = U.OpenSSL = { stringify: function(b) {
                  var A, D = b.ciphertext, w = b.salt;
                  return w ? A = o.create([1398893684, 1701076831]).concat(w).concat(D) : A = D, A.toString(u);
                }, parse: function(b) {
                  var A, D = u.parse(b), w = D.words;
                  return w[0] == 1398893684 && w[1] == 1701076831 && (A = o.create(w.slice(2, 4)), w.splice(0, 4), D.sigBytes -= 16), v.create({ ciphertext: D, salt: A });
                } }, L = n.SerializableCipher = i.extend({ cfg: i.extend({ format: R }), encrypt: function(b, A, D, w) {
                  w = this.cfg.extend(w);
                  var H = b.createEncryptor(D, w), O = H.finalize(A), P = H.cfg;
                  return v.create({ ciphertext: O, key: D, iv: P.iv, algorithm: b, mode: P.mode, padding: P.padding, blockSize: b.blockSize, formatter: w.format });
                }, decrypt: function(b, A, D, w) {
                  w = this.cfg.extend(w), A = this._parse(A, w.format);
                  var H = b.createDecryptor(D, w).finalize(A.ciphertext);
                  return H;
                }, _parse: function(b, A) {
                  return typeof b == "string" ? A.parse(b, this) : b;
                } }), N = t.kdf = {}, k = N.OpenSSL = { execute: function(b, A, D, w, H) {
                  if (w || (w = o.random(64 / 8)), H) var O = h.create({ keySize: A + D, hasher: H }).compute(b, w);
                  else var O = h.create({ keySize: A + D }).compute(b, w);
                  var P = o.create(O.words.slice(A), D * 4);
                  return O.sigBytes = A * 4, v.create({ key: O, iv: P, salt: w });
                } }, T = n.PasswordBasedCipher = L.extend({ cfg: L.cfg.extend({ kdf: k }), encrypt: function(b, A, D, w) {
                  w = this.cfg.extend(w);
                  var H = w.kdf.execute(D, b.keySize, b.ivSize, w.salt, w.hasher);
                  w.iv = H.iv;
                  var O = L.encrypt.call(this, b, A, H.key, w);
                  return O.mixIn(H), O;
                }, decrypt: function(b, A, D, w) {
                  w = this.cfg.extend(w), A = this._parse(A, w.format);
                  var H = w.kdf.execute(D, b.keySize, b.ivSize, A.salt, w.hasher);
                  w.iv = H.iv;
                  var O = L.decrypt.call(this, b, A, H.key, w);
                  return O;
                } });
              })();
            });
          });
          var Jr = z((nt, Wr) => {
            (function(r, e, t) {
              typeof nt == "object" ? Wr.exports = nt = e(X(), Pr(), Ft(), kt(), Rt()) : typeof define == "function" && define.amd ? define(["./core", "./enc-base64", "./md5", "./evpkdf", "./cipher-core"], e) : e(r.CryptoJS);
            })(nt, function(r) {
              return (function() {
                var e = r, t = e.lib, n = t.BlockCipher, i = e.algo, o = [], a = [], c = [], s = [], u = [], f = [], h = [], d = [], x = [], y = [];
                (function() {
                  for (var l = [], p = 0; p < 256; p++) p < 128 ? l[p] = p << 1 : l[p] = p << 1 ^ 283;
                  for (var g = 0, v = 0, p = 0; p < 256; p++) {
                    var U = v ^ v << 1 ^ v << 2 ^ v << 3 ^ v << 4;
                    U = U >>> 8 ^ U & 255 ^ 99, o[g] = U, a[U] = g;
                    var R = l[g], L = l[R], N = l[L], k = l[U] * 257 ^ U * 16843008;
                    c[g] = k << 24 | k >>> 8, s[g] = k << 16 | k >>> 16, u[g] = k << 8 | k >>> 24, f[g] = k;
                    var k = N * 16843009 ^ L * 65537 ^ R * 257 ^ g * 16843008;
                    h[U] = k << 24 | k >>> 8, d[U] = k << 16 | k >>> 16, x[U] = k << 8 | k >>> 24, y[U] = k, g ? (g = R ^ l[l[l[N ^ R]]], v ^= l[l[v]]) : g = v = 1;
                  }
                })();
                var I = [0, 1, 2, 4, 8, 16, 32, 64, 128, 27, 54], F = i.AES = n.extend({ _doReset: function() {
                  var l;
                  if (!(this._nRounds && this._keyPriorReset === this._key)) {
                    for (var p = this._keyPriorReset = this._key, g = p.words, v = p.sigBytes / 4, U = this._nRounds = v + 6, R = (U + 1) * 4, L = this._keySchedule = [], N = 0; N < R; N++) N < v ? L[N] = g[N] : (l = L[N - 1], N % v ? v > 6 && N % v == 4 && (l = o[l >>> 24] << 24 | o[l >>> 16 & 255] << 16 | o[l >>> 8 & 255] << 8 | o[l & 255]) : (l = l << 8 | l >>> 24, l = o[l >>> 24] << 24 | o[l >>> 16 & 255] << 16 | o[l >>> 8 & 255] << 8 | o[l & 255], l ^= I[N / v | 0] << 24), L[N] = L[N - v] ^ l);
                    for (var k = this._invKeySchedule = [], T = 0; T < R; T++) {
                      var N = R - T;
                      if (T % 4) var l = L[N];
                      else var l = L[N - 4];
                      T < 4 || N <= 4 ? k[T] = l : k[T] = h[o[l >>> 24]] ^ d[o[l >>> 16 & 255]] ^ x[o[l >>> 8 & 255]] ^ y[o[l & 255]];
                    }
                  }
                }, encryptBlock: function(l, p) {
                  this._doCryptBlock(l, p, this._keySchedule, c, s, u, f, o);
                }, decryptBlock: function(l, p) {
                  var g = l[p + 1];
                  l[p + 1] = l[p + 3], l[p + 3] = g, this._doCryptBlock(l, p, this._invKeySchedule, h, d, x, y, a);
                  var g = l[p + 1];
                  l[p + 1] = l[p + 3], l[p + 3] = g;
                }, _doCryptBlock: function(l, p, g, v, U, R, L, N) {
                  for (var k = this._nRounds, T = l[p] ^ g[0], b = l[p + 1] ^ g[1], A = l[p + 2] ^ g[2], D = l[p + 3] ^ g[3], w = 4, H = 1; H < k; H++) {
                    var O = v[T >>> 24] ^ U[b >>> 16 & 255] ^ R[A >>> 8 & 255] ^ L[D & 255] ^ g[w++], P = v[b >>> 24] ^ U[A >>> 16 & 255] ^ R[D >>> 8 & 255] ^ L[T & 255] ^ g[w++], q = v[A >>> 24] ^ U[D >>> 16 & 255] ^ R[T >>> 8 & 255] ^ L[b & 255] ^ g[w++], _ = v[D >>> 24] ^ U[T >>> 16 & 255] ^ R[b >>> 8 & 255] ^ L[A & 255] ^ g[w++];
                    T = O, b = P, A = q, D = _;
                  }
                  var O = (N[T >>> 24] << 24 | N[b >>> 16 & 255] << 16 | N[A >>> 8 & 255] << 8 | N[D & 255]) ^ g[w++], P = (N[b >>> 24] << 24 | N[A >>> 16 & 255] << 16 | N[D >>> 8 & 255] << 8 | N[T & 255]) ^ g[w++], q = (N[A >>> 24] << 24 | N[D >>> 16 & 255] << 16 | N[T >>> 8 & 255] << 8 | N[b & 255]) ^ g[w++], _ = (N[D >>> 24] << 24 | N[T >>> 16 & 255] << 16 | N[b >>> 8 & 255] << 8 | N[A & 255]) ^ g[w++];
                  l[p] = O, l[p + 1] = P, l[p + 2] = q, l[p + 3] = _;
                }, keySize: 256 / 32 });
                e.AES = n._createHelper(F);
              })(), r.AES;
            });
          });
          var Gr = z((it, Kr) => {
            (function(r, e, t) {
              typeof it == "object" ? Kr.exports = it = e(X(), Rt()) : typeof define == "function" && define.amd ? define(["./core", "./cipher-core"], e) : e(r.CryptoJS);
            })(it, function(r) {
              return r.pad.NoPadding = { pad: function() {
              }, unpad: function() {
              } }, r.pad.NoPadding;
            });
          });
          var Qr = z((Uo, Zr) => {
            var { Buffer: se } = Je(), ge = X();
            Ft();
            Hr();
            Jr();
            Gr();
            function ot(r) {
              let e = se.from(r), t = [];
              for (let n = 0; n < e.length; n++) t[n >>> 2] = (t[n >>> 2] || 0) | e[n] << 24 - n % 4 * 8;
              return ge.lib.WordArray.create(t, e.length);
            }
            function Yr(r) {
              let e = se.alloc(r.sigBytes);
              for (let t = 0; t < e.length; t++) e[t] = r.words[t >>> 2] >>> 24 - t % 4 * 8 & 255;
              return e;
            }
            function Xr(r) {
              let e = [];
              return { update(t) {
                return e.push(se.from(t)), this;
              }, digest(t) {
                let n = Yr((r === "md5" ? ge.MD5 : ge.SHA512)(ot(se.concat(e))));
                return t ? n.toString(t) : n;
              } };
            }
            function Ci(r, e, t) {
              if (r !== "aes-128-cbc") throw new Error("Unsupported cipher");
              let n = [];
              return { setAutoPadding(i) {
                if (i) throw new Error("Unsupported padding");
              }, update(i) {
                return n.push(se.from(i)), se.alloc(0);
              }, final() {
                return Yr(ge.AES.decrypt(ge.lib.CipherParams.create({ ciphertext: ot(se.concat(n)) }), ot(e), { iv: ot(t), mode: ge.mode.CBC, padding: ge.pad.NoPadding }));
              } };
            }
            var Si = 0;
            function Ui(r) {
              if (globalThis.crypto && typeof globalThis.crypto.getRandomValues == "function") {
                let t = new Uint8Array(r);
                return globalThis.crypto.getRandomValues(t), se.from(t);
              }
              let e = [];
              for (; e.length * 64 < r; ) e.push(Xr("sha512").update(String(globalThis.__hongguoEntropy || Math.random()) + ":" + Date.now() + ":" + Si++).digest());
              return se.concat(e).subarray(0, r);
            }
            Zr.exports = { createHash: Xr, createDecipheriv: Ci, randomBytes: Ui };
          });
          var tn = z((Fo, en) => {
            var { Buffer: at } = Je();
            en.exports = function(e) {
              let t = at.isBuffer(e) ? e : at.from(e), n = at.alloc(Math.ceil((t.length + 9) / 64) * 64);
              t.copy(n), n[t.length] = 128;
              let i = t.length * 8;
              n.writeUInt32BE(Math.floor(i / 4294967296), n.length - 8), n.writeUInt32BE(i >>> 0, n.length - 4);
              let o = new Uint32Array([1937774191, 1226093241, 388252375, 3666478592, 2842636476, 372324522, 3817729613, 2969243214]), a = new Uint32Array(68), c = (u, f) => (u << (f & 31) | u >>> (32 - f & 31)) >>> 0;
              for (let u = 0; u < n.length; u += 64) {
                for (let g = 0; g < 16; g++) a[g] = n.readUInt32BE(u + g * 4);
                for (let g = 16; g < 68; g++) {
                  let v = a[g - 16] ^ a[g - 9] ^ c(a[g - 3], 15);
                  a[g] = v ^ c(v, 15) ^ c(v, 23) ^ c(a[g - 13], 7) ^ a[g - 6];
                }
                let [f, h, d, x, y, I, F, l] = o;
                for (let g = 0; g < 64; g++) {
                  let v = c(f, 12), U = c(v + y + c(g < 16 ? 2043430169 : 2055708042, g) >>> 0, 7), R = U ^ v, L = g < 16 ? f ^ h ^ d : f & h | f & d | h & d, N = g < 16 ? y ^ I ^ F : y & I | ~y & F, k = L + x + R + (a[g] ^ a[g + 4]) >>> 0, T = N + l + U + a[g] >>> 0;
                  x = d, d = c(h, 9), h = f, f = k, l = F, F = c(I, 19), I = y, y = (T ^ c(T, 9) ^ c(T, 17)) >>> 0;
                }
                let p = [f, h, d, x, y, I, F, l];
                for (let g = 0; g < 8; g++) o[g] ^= p[g];
              }
              let s = at.alloc(32);
              for (let u = 0; u < 8; u++) s.writeUInt32BE(o[u], u * 4);
              return s;
            };
          });
          var on = z((ko, nn) => {
            var Fi = ["auto", "1080p", "720p"];
            function rn(r = "auto") {
              if (!Fi.includes(r)) throw new Error("\u4E0B\u8F7D\u6E05\u6670\u5EA6\u65E0\u6548\uFF0C\u8BF7\u9009\u62E9\u81EA\u52A8\u30011080p \u6216 720p");
              return r;
            }
            function ki({ width: r, height: e } = {}, t = "auto") {
              if (t = rn(t), t === "auto") return true;
              let n = [Number(r), Number(e)];
              return n.every((i) => Number.isFinite(i) && i > 0) && Math.min(...n) >= Number.parseInt(t, 10);
            }
            nn.exports = { normalizeDownloadQuality: rn, meetsDownloadQuality: ki };
          });
          var pt = z((Ro, mn) => {
            var dn = ur(), { Buffer: S } = Je(), K = Qr(), ht = tn(), { normalizeDownloadQuality: Ri, meetsDownloadQuality: Di } = on(), an = () => String(1e15 + parseInt(K.randomBytes(6).toString("hex"), 16)), pn = K.randomBytes(18).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""), ct = Date.now(), xn = "https://api5-normal-sinfonlineb.fqnovel.com/novel/player/multi_video_model/v1/", dt = "com.phoenix.read/71332 (Linux; U; Android 16; zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; Cronet/TTNetVersion:04657795 2026-01-23 QuicVersion:c67e9834 2025-09-08)", yn = { ac: "wifi", channel: "update_64", aid: "8662", app_name: "novelread", version_code: "71332", version_name: "7.1.3.32", device_platform: "android", os: "android", ssmix: "a", device_type: "25053RT47C", device_brand: "Redmi", language: "zh", os_api: "36", os_version: "16", manifest_version_code: "71332", resolution: "1280*2772", dpi: "520", update_version_code: "71332", host_abi: "arm64-v8a", dragon_device_type: "phone", pv_player: "71332", compliance_status: "0", need_personal_recommend: "1", player_so_load: "1", is_android_pad_screen: "0" };
            function fe(r, e = "") {
              return String(r != null ? r : e).trim();
            }
            function cn(r) {
              return fe(r).replace(/\\\//g, "/").replace(/\\u0026/g, "&").replace(/&amp;/g, "&");
            }
            function Lt(r) {
              try {
                return JSON.parse(String(r).replace(/(\"(?:[A-Za-z0-9_]*_id|id)\"\s*:\s*)(-?\d{16,})(?=\s*[,}\]])/g, '$1"$2"'));
              } catch (e) {
                return null;
              }
            }
            function Ni(r) {
              return Object.entries(r).map(([e, t]) => {
                let n = (i) => encodeURIComponent(String(i != null ? i : "")).replace(/[!'()]/g, (o) => `%${o.charCodeAt(0).toString(16).toUpperCase()}`);
                return `${n(e)}=${n(t)}`;
              }).join("&");
            }
            function Ti(r) {
              return K.createHash("md5").update(r).digest("hex").toUpperCase();
            }
            function M(r) {
              return Number(r) >>> 0;
            }
            function re(r, e) {
              let t = e & 31, n = M(r);
              return M(n << t | n >>> 32 - t);
            }
            function ne(r, e) {
              let t = e & 31, n = M(r);
              return M(n >>> t | n << 32 - t);
            }
            function st(r, e) {
              return [(r[0] ^ e[0]) >>> 0, (r[1] ^ e[1]) >>> 0];
            }
            function sn(r, e) {
              let t = r[0] + e[0];
              return [t >>> 0, r[1] + e[1] + (t >= 4294967296 ? 1 : 0) >>> 0];
            }
            function ft(r, e) {
              let t = r[0], n = r[1], i = e & 63;
              if (i >= 32) {
                let o = t;
                t = n, n = o, i -= 32;
              }
              return i ? [(t >>> i | n << 32 - i) >>> 0, (n >>> i | t << 32 - i) >>> 0] : [t, n];
            }
            function Dt(r, e) {
              return [r.readUInt32LE(e), r.readUInt32LE(e + 4)];
            }
            function fn(r, e, t) {
              r.writeUInt32LE(e[0], t), r.writeUInt32LE(e[1], t + 4);
            }
            function Z(r) {
              let e = S.alloc(4);
              return e.writeUInt32LE(M(r)), e;
            }
            function gn(r) {
              let e = S.alloc(4);
              return e.writeUInt32BE(M(r)), e;
            }
            function Li(r) {
              let e = Number(r);
              return e < 0 ? -e * 2 - 1 : e * 2;
            }
            function He(r) {
              let e = Number(r);
              if (!Number.isSafeInteger(e) || e < 0) throw new Error("Invalid integer");
              let t = [];
              for (; e > 127; ) t.push(e % 128 | 128), e = Math.floor(e / 128);
              return t.push(e), S.from(t);
            }
            function Hi(r, e, t = "string") {
              if (e == null || e === "") return S.alloc(0);
              if (t === "bytes" || t === "string" || t === "message") {
                let n = t === "bytes" ? S.from(e) : t === "message" ? e : S.from(String(e));
                return S.concat([He(r * 8 + 2), He(n.length), n]);
              }
              if (t === "float") {
                let n = S.alloc(4);
                return n.writeFloatLE(Number(e)), S.concat([He(r * 8 + 5), n]);
              }
              return S.concat([He(r * 8), He(t === "sint" ? Li(e) : e)]);
            }
            function Oe(r) {
              return S.concat(r.map(([e, t, n]) => Hi(e, t, n)));
            }
            function Ce(r, e) {
              let t = M(r);
              for (let n = 0; n < e.length; n += 1) (n & 1) === 0 ? t = M(t >>> 4 ^ t ^ t << 6 ^ e[n]) : t = M(~(t >>> 7 ^ t ^ (e[n] | t << 12)));
              return t;
            }
            function Nt(r) {
              let e = 539100192;
              for (let t = 0; t < 12; t += 1) {
                let n = (t & 1) === 0 ? e >>> 3 ^ e : e >>> 5 ^ e;
                e = (t & 1) === 0 ? r[t] ^ e << 7 : r[t] | e << 11, (t & 1) !== 0 && (e = ~e), e = M(e ^ n);
              }
              return M((e | 4) ^ 16777216);
            }
            var Oi = [2813263392, 1900671446, 1206176263, 3920990055, 2478384350, 3323252981, 951050479, 2998644083, 3796124867, 2637884571, 3749394404, 3635506496, 4172034488, 1991878923, 836252654, 2503986788, 892704164, 1175044411, 915558408, 2355956005, 1576386935, 486274347, 2320476144, 290235230, 2173958532, 2054850355, 829076693, 1008783305, 2799191123, 974671884, 2039399546, 2544331560, 1724186518, 1366385731, 231930939, 3043585447, 3152755397, 1548997124, 3542485198, 1920580076, 4095250127, 4158100443, 858571921, 2876681749, 2615928615, 413143940, 1542060199, 1603315540, 968254400, 912735363, 2090005780, 2642253015, 3806910890, 1602133673, 2059224401, 1453196762, 1084380722, 1039509925, 3132325248, 1161987804, 1063079544, 64468829, 2986232567, 2779457187], Pi = S.from("0f0704000908030a060b050d0e010c020f05080c0009020103070e060b0a0d04060500070c000a04080f010b0d09020e060b02050403080101070a000d0c090e0d070e0f0b0208030c0509010004060a0d0902060f0b0a040807000c0503010e0c090f07060f030e020d0405010b0a000c050a090e0802040407030f01060b000b0f0408020a0700090d06010e03050c0b060a0508020c03070f0e090d0001040906080f050800040a0b030d01020c0e090d0c0604070a03030f00080105020e01000d0f090a0b0e0402080703060c0501080a0c0f0905060b000304020e070d04080f000c0f0e0d0a01060207090503040205080d0b0a0606000e0f070c09030a08040f000b01060d0c0709030e05020a070b050f00020e0108030d0c0609040d070f08050f06040b0a0e0c090002030d0c020704010b0e0e08060f09050003", "hex");
            function ut(r, e, t, n, i, o, a, c) {
              let s;
              return r === 0 ? s = t & n | ~t & i : r === 1 ? s = t & i | n & ~i : r === 2 ? s = t ^ n ^ i : s = n ^ (t | ~i), M(t + re(M(e + s + o + c), a));
            }
            function Mi(r, e, t, n) {
              let i = Oi.map((I) => ne(I, n)), o = [ne(2044785403, e), ne(3367314800, e), ne(3955423437, e), ne(2081443219, e)], a = e + 6 & 255, c = [ne(431900774, a), ne(3898181300, a), ne(3785044590, a), ne(1909577684, a)], s = [];
              for (let I = 0; I < 16; I += 1) s.push(r.readUInt32LE(I * 4));
              let [u, f, h, d] = o, x = (I, F, l, p) => {
                for (let g = 0; g < 16; g += 1) {
                  let v = g & 3, U = v === 0 ? ut(I, u, f, h, d, s[t[p + g]], l[g], i[p + g]) : v === 1 ? ut(I, d, u, f, h, s[t[p + g]], l[g], i[p + g]) : v === 2 ? ut(I, h, d, u, f, s[t[p + g]], l[g], i[p + g]) : ut(I, f, h, d, u, s[t[p + g]], l[g], i[p + g]);
                  v === 0 ? u = U : v === 1 ? d = U : v === 2 ? h = U : f = U;
                }
              };
              x(0, t, [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22], 0), x(1, t, [5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20], 16), x(2, t, [4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23], 32), x(3, t, [6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21], 48);
              let y = S.alloc(16);
              return y.writeUInt32LE(M(o[0] + u ^ c[0]), 0), y.writeUInt32LE(M(o[1] + f ^ c[1]), 4), y.writeUInt32LE(M(o[2] + h ^ c[2]), 8), y.writeUInt32LE(M(o[3] + d ^ c[3]), 12), S.concat([y, Z(Nt(y))]);
            }
            function zi(r, e, t, n, i) {
              let o = (r & 13) * 86, a = (o >>> 15 & 255) + (o >>> 8 & 255), c = [2306929307, 3948190847, 2961647323, 3557602790, 3908393444][a], s = c + i + 1 & 255, u = M(c + i), f = u + 5 & 7, h = [132, 150, 119, 157, 212, 21, 11, 248], d = S.from(h.map((y) => (y | y << 8) >> f & 255)), x = S.concat([e, t, n, d, S.from("a0010000", "hex")]);
              return Mi(x, u, Pi.subarray(a << 6, a + 1 << 6), s);
            }
            function qi(r, e) {
              let t = S.alloc(Math.min(r.length, e.length));
              for (let n = 0; n < t.length; n += 1) t[n] = r[n] ^ e[n];
              return t;
            }
            function ji(r, e, t, n) {
              let i = Ce(Ce(Ce(539167016, r), e), t), o = i & 15, a = o * 171 >> 9, c = o - a * 3;
              if (c === 2) return zi(i, r, e, t, n);
              if (c !== 0) return S.concat([r.subarray(0, 16), e, Z(Nt(S.concat([r, e])))]);
              let u = [3299313024, 3015769401, 3314308742, 3383376807, 4121406962, 2520526545][a], f = u + n + 1 & 255, h = M(u + n), x = [3954593711, 128638146, 3476129727, 3759225087, 1829502207, 1513137086, 3021657656, 873991864, 4063488879, 2980414668, 3435335111, 1204935505, 3579204574, 1890078625, 1464286226, 4151247496, 738688778, 3658336976, 4223168364, 4257533696, 1753874957, 3866543782, 2362848139, 440175886, 3437801579, 1792077067, 2689738519, 3698437251, 579197809, 3585400230, 1936688720, 1700802668, 1635574438, 3827515774, 172024131, 1414414386, 2296380202, 1902910176, 1279687304, 95566771, 3788552294, 3131301048, 2922607827, 3275233872, 386070363, 4268598120, 4038381384, 1309670328, 1923797261, 650459709, 4072464630, 3025499521, 1243971549, 2352054946, 2869640070, 1029569300, 1326462516, 3548074711, 1146027798, 3943314385, 1822977902, 2640807, 137919738, 1605596550].map((k) => ne(k, f)), y = h + 2 & 7, I = [250, 69, 97, 215], F = S.from(I.map((k) => (k | k << 8) >> y & 255)), l = S.concat([r, e, t, F, S.from("00000000000001a0", "hex")]), p = [];
              for (let k = 0; k < l.length; k += 4) p.push(l.readUInt32BE(k));
              let g = p[0];
              for (let k = 0; k < 112; k += 1) {
                let T = p[k + 1], b = p[k + 14], A = re(T, 14) ^ re(T, 25) ^ T >>> 3, D = re(b, 13) ^ re(b, 15) ^ b >>> 10;
                p.push(M(g + p[k + 9] + A + D)), g = T;
              }
              let v = [2059030472, 1729520903, 1677982208, 873419055, 984304912, 3005047866, 2874125293, 2152413264].map((k) => ne(k, h & 31)), U = [[101, 5, 7, 6, 3, 2, 1, 0, 5, 4, 3], [96, 0, 6, 7, 5, 3, 2, 1, 5, 4, 4], [96, 7, 6, 2, 1, 4, 0, 5, 4, 3, 5], [99, 3, 6, 2, 4, 5, 1, 0, 0, 7, 6], [96, 0, 5, 6, 7, 3, 1, 2, 5, 4, 4], [100, 2, 0, 3, 5, 4, 6, 7, 2, 1, 5]][a], R = v.slice();
              for (let k = 0; k < U[0]; k += 1) {
                let T = u + k, b = p[T & 127], A = (R[U[3]] ^ R[U[4]]) & R[U[1]] ^ R[U[3]], D = re(R[U[1]], 26) ^ re(R[U[1]], 21) ^ re(R[U[1]], 7), w = M(b + A + D + x[T & 63] + R[U[5]]), H = re(R[U[2]], 30) ^ re(R[U[2]], 19) ^ re(R[U[2]], 10), O = R[U[2]] & R[U[6]] | (R[U[2]] | R[U[6]]) & R[U[7]], P = M(H + O), q = R[U[9]];
                R.unshift(R.pop()), R[U[10]] = M(P + w), R[U[8]] = M(q + w);
              }
              let L = S.alloc(32);
              for (let k = 0; k < 8; k += 1) L.writeUInt32BE(M(R[k] + v[k]), k * 4);
              return qi(L.subarray(0, 16), L.subarray(16)).copy(L, 0), S.concat([L.subarray(0, 16), Z(Nt(L.subarray(0, 16)))]);
            }
            function Vi(r) {
              let e = 0;
              for (let t = 0; t < 8; t += 1) e = e << 1 | r >> t & 1;
              return e;
            }
            function $i(r, e) {
              let t = Array.from({ length: 256 }, (o, a) => a), n = 0;
              for (let o = 0; o < 256; o += 1) n = n + t[o] + e[o % e.length] & 255, t[o] = t[n];
              let i = 0;
              return n = 0, S.from(r.map((o) => {
                i += 1;
                let a = t[i];
                n += a;
                let c = t[n & 255];
                return t[i] = c, o ^ t[c + c & 255];
              }));
            }
            function Wi(r, e, t, n) {
              let i = S.alloc(4);
              i.writeUInt32LE(67503104);
              let o = S.concat([K.createHash("md5").update(r).digest().subarray(0, 4), e ? K.createHash("md5").update(e).digest().subarray(0, 4) : S.alloc(4), S.alloc(4), i, gn(t)]), a = [74, 64, 22, n >> 8 & 255, 71, 108, 1, n & 255], c = $i([...o], a);
              for (let s = 0; s < c.length; s += 1) {
                let u = c[s];
                u = (u >> 4 | u << 4) & 255;
                let f = s + 1 < c.length ? c[s + 1] : c[0];
                c[s] = ~(Vi((f ^ u) & 255) ^ 20) & 255;
              }
              return S.concat([S.from("8404", "hex"), S.from([n & 255, n >> 8 & 255, 64, 1]), c]).toString("hex");
            }
            function Ji(r) {
              return Oe([[1, 1, "sint"], [2, 2, "sint"], [3, "8662"], [4, r], [5, pn], [6, "!noperm!"], [7, -888888, "sint"], [8, -888888, "sint"], [9, 3, "sint"], [10, -888888, "sint"], [11, "!notset!"], [12, "Asia/Shanghai,8"], [13, "zh_CN"], [14, 4, "sint"], [16, 0, "float"], [17, 0, "float"], [18, 0, "float"], [19, 0, "float"], [20, 0, "float"], [21, 0, "float"], [22, "16"], [23, 41, "sint"], [24, 36, "sint"], [25, ct, "sint"], [26, ct, "sint"], [27, ct, "sint"], [28, ct, "sint"], [29, -1, "sint"], [30, "25053RT47C"], [31, "Redmi"], [32, "25053RT47C"], [33, "25053RT47C"], [34, "Xiaomi"], [35, "Redmi"], [36, "Redmi"], [38, 31, "sint"]]);
            }
            var Ki = S.from("+n0Ia5xZs0sEXznQOEqRmQBnpiCf9U2Ccybu3xhmgzOAAxn72f6uqqmwUsYL83klTni0NqxdGieeiNu9PGPsSRXBMB/cuFbUbM3KCUPINaPvHvSW0vwOcnuUhNHqRVpiAj/TEoE0K91+5ijypUYTATsh9mE3KSoN7Yyvv51cuyR2D3XkU4nhmI2xmmVwT1RMWKtub4sjxAcRDLrPoKSO2AU9FLLadMPX577Wf95IFj6FkKFVt3dCIsmGUC4X+WQxLJvxbRxEaOPpqJOXyzJX6+Vxaq3AzMfF/WAdoi1Hp+JRaV56zgpBtpWP97mH4DoGEIq1+FvV8LyS/3wvwugbQOwb2r26mJEMsiuDQTRn+wrYdrVGBVlhI3WQhyrjUBVMrLF5667llUcEaPCGPVGLD8qO5LlO8hKCvA7V9+8oJc9bXelqVQLhM76T5/WtnT45JKji+hdX0HoNCDDWuKON/QeaxB5uImSX0h2wv0VmP2zd2yeApxHcpsVS+MC2yFwAc2B7oBkTqsk1SEvTpM2fmfMQREBUfin0Bh+iq6EvPPavhWI2IX9e3yAas7Tm/3KEj2UmlFp36kN4x0rMLBRrxuh0U/zUHM4xcAMYjJY4MonxOl/X+alpt2M3WMI7w3HLnpIBigtNiJu7T21v4P6lSd5WFgntnMEt7oF92XzRLkJbTcGmXepE/UVOG6E/0YnhfS+q26utWcuxzpooyeD2cDlK1/8w9d28VzsRjbLuALbmGlp8+d7EzS6Au7lMpZ+ECMZvQmzwJ+eLOpxR+2chdUExp8ogQyq3v9l68rX4jCwjg0+PYKAEEzcU4wHFY2ZcdIHfWL1okD3SszT0GZMyKdZJrg1L2AeerB4tC0C4crp2EHGo5FYdSP7lwkeR2ocmnR+Ia8CYviUJlzOjhRZef9xuVOn3qcjow3fQgivsAmKKkg4+sA8F8/GWeDiGNhg8JM8KtFPMYWWkx5TVFX5t73kiNRJqjlIGVXtGZFCV4gzt0xcDopuZ6xz8r9Rzafpf9ywev8jh8592gHFIqpStZPuJxmDDMrNN0uBE3V+oscdoIzTJbRJ/t+sVvqnReJOgDJKk10fjisJwqyZBmnmn2BSFj8BvVtCMEbkuPOKdzw7eA11GPs04Qw8zWtkaZWwiO/wwpojqN6K0jY5RnNZA7vn4hPSul+nKCkVnVwQvg1zVxcSCtqORmB9KrJaBbssbCQivGJVJfVTt+hYxOtq4ZvWl8f4QAQZ0zGPffCgl9s6yT4vlvIdpu4YhBwA25wtQWZsc6GJYGWHyvSdeuh3mmUI9DSq13Fsp8C1MU3tqc04/df9LoTUXVXI5INOw/e8C7Hd+5CvbkMEFnnrUUmskEw==", "base64");
            function un(r, e) {
              let t = S.from(r);
              for (let n = 0; n < t.length; n += 1) t[n] ^= e[n % e.length];
              return t;
            }
            function Gi(r) {
              return Array.from({ length: 4 }, (e, t) => Array.from(r.subarray(t * 4, t * 4 + 4)));
            }
            function hn(r) {
              return S.from(r.flat());
            }
            function Yi(r) {
              for (let e = 0; e < 4; e += 1) {
                let t = r[0][e] ^ r[1][e] ^ r[2][e] ^ r[3][e], n = r[0][e], i = (o) => (o << 1 ^ (o & 128 ? 27 : 0)) & 255;
                r[0][e] ^= t ^ i(r[0][e] ^ r[1][e]), r[1][e] ^= t ^ i(r[1][e] ^ r[2][e]), r[2][e] ^= t ^ i(r[2][e] ^ r[3][e]), r[3][e] ^= t ^ i(r[3][e] ^ n);
              }
            }
            var Tt = class {
              constructor(e, t) {
                this.wordSize = t & 3, this.box = Ki.subarray(this.wordSize * 256, (this.wordSize + 1) * 256), this.con = [[1, 0, 2, 3], [1, 3, 0, 2], [0, 1, 3, 2], [1, 0, 2, 3]][this.wordSize], this.con2 = [[1, 0, 2, 3], [2, 0, 3, 1], [0, 1, 3, 2], [1, 0, 2, 3]][this.wordSize], this.order = [[0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3], [0, 9, 14, 15, 4, 13, 2, 7, 8, 1, 6, 3, 12, 5, 10, 11], [0, 9, 14, 7, 4, 13, 2, 11, 8, 1, 6, 3, 12, 5, 10, 15], [0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3]][this.wordSize];
                let n = [3389152732, 2185086278, 3376547203, 3264750175][this.wordSize], i = S.alloc(16);
                for (let s = 0; s < 4; s += 1) i.writeUInt32LE(n, s * 4);
                let o = un(i, e), a = S.concat([o, S.alloc(32)]), c = 8;
                for (let s = 4; s < 12; s += 1) {
                  let u = 4 * (s - 1), f = a[u], h = a[u + 1], d = a[u + 2], x = a[u + 3];
                  if ((s & 3) === 0) {
                    let y = (M(n >> (c & 24)) ^ this.box[h]) & 255;
                    h = this.box[d], d = this.box[x], x = this.box[f], f = y;
                  }
                  c += 2, a[u + 4] = f ^ a[u - 12], a[u + 5] = h ^ a[u - 11], a[u + 6] = d ^ a[u - 10], a[u + 7] = x ^ a[u - 9];
                }
                this.keys = Array.from({ length: 12 }, (s, u) => Array.from(a.subarray(u * 4, u * 4 + 4)));
              }
              add(e, t) {
                for (let n = 0; n < 4; n += 1) for (let i = 0; i < 4; i += 1) e[n][i] ^= t[n][i];
              }
              addCon(e, t) {
                for (let n = 0; n < 4; n += 1) for (let i = 0; i < 4; i += 1) e[n][i] ^= t[n][this.con2[i]];
              }
              sub(e) {
                for (let n = 0; n < 4; n += 1) for (let i = 0; i < 4; i += 1) e[n][i] = this.box[e[n][i]];
                let t = e.map((n) => n.slice());
                for (let n = 0; n < 4; n += 1) e[n] = t[this.con2[n]];
              }
              shift(e) {
                let t = hn(e);
                for (let n = 0; n < 16; n += 1) e[Math.floor(n / 4)][n % 4] = t[this.order[n]];
              }
              shiftCon(e) {
                let t = e.map((n) => n.slice());
                for (let n = 0; n < 4; n += 1) e[n] = this.con2.map((i) => t[n][i]);
              }
              block(e) {
                let t = Gi(e);
                this.addCon(t, this.keys.slice(0, 4));
                for (let n = 1; n < 3; n += 1) this.sub(t), this.shift(t), n === 1 && (this.shiftCon(t), Yi(t)), this.addCon(t, this.keys.slice(n * 4));
                return this.add(t, this.keys.slice(4)), hn(t);
              }
              encrypt(e, t) {
                let n = S.from(e), i = S.alloc(32);
                for (let u = 0; u < 31; u += 1) {
                  let f = u * 8, l = n[f] >> 4 & 2 | n[f + 1] & 64 | n[f + 2] >> 2 & 1 | n[f + 3] << 3 & 128 | n[f + 4] >> 1 & 4 | n[f + 5] << 3 & 16 | n[f + 6] << 5 & 32;
                  i[u] = l | n[f + 7] >> 4 & 8;
                }
                i[31] = 1;
                let o = [], a = S.from(t);
                for (let u = 0; u < i.length; u += 16) {
                  let f = this.block(un(i.subarray(u, u + 16), a));
                  o.push(f), a = f;
                }
                let c = S.concat(o), s = S.from(n);
                for (let u = 0; u < 31; u += 1) {
                  let f = u * 8, h = c[u];
                  s[f] &= 223, s[f] |= h << 4 & 32, s[f + 1] &= 191, s[f + 1] |= h & 64, s[f + 2] &= 251, s[f + 2] |= h << 2 & 4, s[f + 3] &= 239, s[f + 3] |= h >> 3 & 16, s[f + 4] &= 247, s[f + 4] |= h + h & 8, s[f + 5] &= 253, s[f + 5] |= h >> 3 & 2, s[f + 6] &= 254, s[f + 6] |= h >> 5 & 1, s[f + 7] &= 127, s[f + 7] |= h << 4 & 128;
                }
                return S.concat([c.subarray(-1), s]);
              }
            };
            function Xi(r, e) {
              let t = S.alloc(r.length);
              for (let a = 0; a < r.length; a += 1) {
                let c = a * 4 & 28, s = e[c], u = e[c + 1], f = ((r[a] << 4 | r[a] >>> 4) & 255) + s;
                f = ~f ^ u, f = ((f & 255) << 3 | (f & 255) >>> 5) & 255, f = f + u & 255, f = (f ^ s) & 255, t[r.length - a - 1] = ~f & 255;
              }
              let n = t[t.length - 1] ^ t[t.length - 2], i = t[0];
              t[0] = ~n + i & 255, t[1] = (t[0] ^ t[t.length - 1] ^ 254) + t[1] & 255, t[2] = t[2] + (n - i ^ (t[1] << 3 | t[1] >>> 5) & 255 ^ 2) & 255;
              for (let a = 0; a < t.length - 4; a += 1) {
                let c = (t[a + 2] << 3 | t[a + 2] >>> 5) & 255 ^ t[a + 1] ^ a + 3;
                t[a + 3] = ~c + t[a + 3] & 255;
              }
              t[t.length - 1] ^= t[t.length - 2];
              let o = 0;
              for (let a = 0; a < t.length - 1; a += 1) o += t[a + 1];
              return t[0] = (t[0] ^ t[1]) + o & 255, t;
            }
            function Zi(r, e) {
              let t = S.concat([r, Z(e), r]), n = ht(t), i = e >> 16 & 255, o = (i << 11 | e >>> 24) ^ i >> 5 ^ i;
              return o = ~o >>> 0, [n, Z(o)];
            }
            function Qi(r, e, t, n) {
              let i = e ? K.createHash("md5").update(e).digest() : S.alloc(16), o = ht(r.split("?")[1]), a = Z(t), c = ji(o, i, a, t), s = Oe([[1, 111, "sint"], [2, 10, "sint"], [3, 694367, "sint"], [5, 586952199, "sint"]]), u = Math.floor(Math.random() * 4294967296), f = Math.floor(Math.random() * 21) + 100, h = Math.floor(Math.random() * 2e3) + 10001, d = Oe([[1, f, "sint"], [2, 146331399, "sint"], [3, 146331396, "sint"], [5, 7, "sint"], [6, "v04.06.04.03-bugfix"], [7, h, "sint"], [12, Ji(n.device_id), "message"], [13, Oe([[1, Math.floor(Date.now() / 1e3), "sint"], [2, -2, "sint"], [4, 200, "sint"]]), "message"], [14, n.version_name]]), x = ht(S.concat([S.from(r.split("?")[1]), i, S.from("none")])), y = Oe([[1, S.from("f7e85ffad7d7dc3bd62ac87057cf6118", "hex"), "bytes"], [2, 3, "sint"], [3, u, "sint"], [4, "8662"], [5, n.device_id], [6, "1588093228"], [7, n.version_name], [8, "v04.06.04-ml-android"], [9, 67503104, "sint"], [10, S.from("4001000000000000", "hex"), "bytes"], [12, t, "sint"], [13, c, "bytes"], [14, o.subarray(0, 6), "bytes"], [15, s, "message"], [16, pn], [17, t, "sint"], [19, x, "bytes"], [20, "none"], [21, 312, "sint"], [23, d, "message"], [24, '{"cmr":16777216,"cmr2":16777216,"un_h":1879194040,"vpn":0,"kd":0,"fkd":3672518972,"pd":-1872573247,"dyn":"","do":0,"tk":true}']]), I = Math.floor(Math.random() * 4294967296), [F, l] = Zi(S.from("8ebdfa3806ecc5cee79423e6029ed82540bc2218bb7eae f71cb691f7aa8aa2f5".replace(/ /g, ""), "hex"), I), p = Xi(y, F);
              p = S.concat([S.from("4001000000000000", "hex"), p]).reverse();
              for (let k = 0; k < p.length; k += 1) p[k] ^= l[~k & 3];
              let g = (o[0] & 63) << 14 | 402653185 | (c[0] & 63) << 8, v = Math.floor(Math.random() * 4294967296), U = S.concat([S.from([53]), Z(v), Z(g), p, S.from([I >> 16, I >> 24])]), R = new Tt(S.from("f1593376766ea98d34f31b057a9d5be4", "hex"), t).encrypt(U, S.from("1fe109a4125283f418de9e051a969e12", "hex")), L = S.from("03000000f7e85ffad7d7dc3bd62ac87057cf6118", "hex"), N = S.alloc(20);
              for (let k = 0; k < 20; k += 4) N.writeUInt32LE(M(L.readUInt32LE(k) ^ t), k);
              return S.concat([N, S.from([I & 255, I >> 8 & 255, 0, 1]), R]).toString("base64");
            }
            function eo(r) {
              let e = Math.floor(Math.random() * 4294967296), t = S.concat([Z(e), S.from("8662")]), n = K.createHash("md5").update(t).digest(), i = S.from(n.toString("hex"), "ascii"), o = [];
              for (let d = 0; d < 4; d += 1) o.push(Dt(i, d * 8));
              let a = [o[0]], c = o[0], s = o[1];
              o.splice(0, 2);
              for (let d = 0; d < 34; d += 1) {
                let x = sn(ft(s, 8), c);
                x = st(x, [d, 0]), o.push(x), x = st(x, ft(c, 61)), a.push(x), c = x, s = o.shift();
              }
              let u = S.from(`${r}-1588093228-8662`), f = S.alloc(Math.ceil((u.length + 1) / 16) * 16, 16 - u.length % 16);
              u.copy(f);
              let h = [];
              for (let d = 0; d < f.length; d += 16) {
                let x = Dt(f, d), y = Dt(f, d + 8);
                for (let F = 0; F < 34; F += 1) y = st(a[F], sn(x, ft(y, 8))), x = st(y, ft(x, 61));
                let I = S.alloc(16);
                fn(I, x, 0), fn(I, y, 8), h.push(I);
              }
              return S.concat([Z(e), ...h]).toString("base64");
            }
            function to(r, e, t) {
              let n = e ? K.createHash("md5").update(e).digest() : S.alloc(16), i = ht(r.split("?")[1]), a = Ce(Ce(Ce(539167016, i), n), Z(t)) & 15;
              return a - (a * 171 >> 9) * 3;
            }
            (function() {
              function PublicMd5Mi(r, e, t, n) {
                let i = Oi.map((I) => ne(I, n)), o = [ne(2044785403, e), ne(3367314800, e), ne(3955423437, e), ne(2081443219, e)], a = e + 6 & 255, c = [ne(431900774, a), ne(3898181300, a), ne(3785044590, a), ne(1909577684, a)], s = [];
                for (let I = 0; I < 16; I += 1) s.push(r.readUInt32LE(I * 4));
                let [u, f, h, d] = o, x = (I, F, l, p) => {
                  for (let g = 0; g < 16; g += 1) {
                    let v = g & 3, U = v === 0 ? ut(I, u, f, h, d, s[t[p + g]], l[g], i[p + g]) : v === 1 ? ut(I, d, u, f, h, s[t[p + g]], l[g], i[p + g]) : v === 2 ? ut(I, h, d, u, f, s[t[p + g]], l[g], i[p + g]) : ut(I, f, h, d, u, s[t[p + g]], l[g], i[p + g]);
                    v === 0 ? u = U : v === 1 ? d = U : v === 2 ? h = U : f = U;
                  }
                };
                x(0, t, [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22], 0), x(1, t, [5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20], 16), x(2, t, [4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23], 32), x(3, t, [6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21], 48);
                let y = S.alloc(16);
                return y.writeUInt32LE(M(o[0] + u ^ c[0]), 0), y.writeUInt32LE(M(o[1] + f ^ c[1]), 4), y.writeUInt32LE(M(o[2] + h ^ c[2]), 8), y.writeUInt32LE(M(o[3] + d ^ c[3]), 12), S.concat([y, Z(Nt(y))]);
              }
              function PublicMd5Zi(r, e, t, n, i) {
                let o = (r & 13) * 86, a = (o >>> 15 & 255) + (o >>> 8 & 255), c = [2560851803, 3874480130, 3239760911, 3714875250, 2728712785][a], s = c + i + 1 & 255, u = M(c + i), f = u + 5 & 7, h = [132, 150, 119, 157, 212, 21, 11, 248], d = S.from(h.map((y) => (y | y << 8) >> f & 255)), x = S.concat([e, t, n, d, S.from("a0010000", "hex")]);
                return PublicMd5Mi(x, u, [[8, 1, 12, 11, 9, 6, 0, 4, 13, 7, 3, 2, 10, 5, 14, 15, 8, 3, 6, 14, 11, 9, 15, 5, 0, 1, 10, 13, 7, 4, 2, 12, 13, 3, 11, 1, 14, 11, 4, 12, 6, 8, 5, 7, 2, 9, 15, 10, 13, 7, 15, 3, 12, 0, 6, 5, 5, 1, 4, 11, 2, 14, 9, 10], [9, 8, 13, 6, 10, 7, 14, 11, 0, 1, 2, 15, 12, 4, 5, 3, 9, 2, 7, 5, 6, 10, 3, 4, 14, 8, 12, 0, 1, 11, 15, 13, 0, 2, 6, 8, 5, 6, 11, 13, 7, 9, 4, 1, 15, 10, 3, 12, 0, 1, 3, 2, 13, 14, 7, 4, 4, 8, 11, 6, 15, 5, 10, 12], [10, 11, 7, 14, 9, 12, 2, 13, 3, 6, 15, 5, 0, 8, 1, 4, 10, 15, 12, 1, 14, 9, 4, 8, 2, 11, 0, 3, 6, 13, 5, 7, 3, 15, 14, 11, 1, 14, 13, 7, 12, 10, 8, 6, 5, 9, 4, 0, 3, 6, 4, 15, 7, 2, 12, 8, 8, 11, 13, 14, 5, 1, 9, 0], [7, 5, 11, 12, 6, 1, 15, 14, 13, 8, 4, 3, 9, 0, 10, 2, 7, 4, 1, 10, 12, 6, 2, 0, 15, 5, 9, 13, 8, 14, 3, 11, 13, 4, 12, 5, 10, 12, 14, 11, 1, 7, 0, 8, 3, 6, 2, 9, 13, 8, 2, 4, 11, 15, 1, 0, 0, 5, 14, 12, 3, 10, 6, 9], [5, 8, 3, 6, 4, 2, 0, 12, 10, 7, 15, 9, 13, 11, 1, 14, 5, 15, 2, 1, 6, 4, 14, 11, 0, 8, 13, 10, 7, 12, 9, 3, 10, 15, 6, 8, 1, 6, 12, 3, 2, 5, 11, 7, 9, 4, 14, 13, 10, 7, 14, 15, 3, 0, 2, 11, 11, 8, 12, 6, 9, 1, 4, 13]][a], s);
              }
              function PublicSha(r, e, t, n, selector) {
                let a = Math.floor(selector / 3);
                let u = [3997655695, 4272070413, 3565944766, 3294847055, 2638911426, 3879464831][a], f = u + n + 1 & 255, h = M(u + n), x = [3954593711, 128638146, 3476129727, 3759225087, 1829502207, 1513137086, 3021657656, 873991864, 4063488879, 2980414668, 3435335111, 1204935505, 3579204574, 1890078625, 1464286226, 4151247496, 738688778, 3658336976, 4223168364, 4257533696, 1753874957, 3866543782, 2362848139, 440175886, 3437801579, 1792077067, 2689738519, 3698437251, 579197809, 3585400230, 1936688720, 1700802668, 1635574438, 3827515774, 172024131, 1414414386, 2296380202, 1902910176, 1279687304, 95566771, 3788552294, 3131301048, 2922607827, 3275233872, 386070363, 4268598120, 4038381384, 1309670328, 1923797261, 650459709, 4072464630, 3025499521, 1243971549, 2352054946, 2869640070, 1029569300, 1326462516, 3548074711, 1146027798, 3943314385, 1822977902, 2640807, 137919738, 1605596550].map((k) => ne(k, f)), y = h + 2 & 7, I = [250, 69, 97, 215], F = S.from(I.map((k) => (k | k << 8) >> y & 255)), l = S.concat([r, e, t, F, S.from("00000000000001a0", "hex")]), p = [];
                for (let k = 0; k < l.length; k += 4) p.push(l.readUInt32BE(k));
                let g = p[0];
                for (let k = 0; k < 112; k += 1) {
                  let T = p[k + 1], b = p[k + 14], A = re(T, 14) ^ re(T, 25) ^ T >>> 3, D = re(b, 13) ^ re(b, 15) ^ b >>> 10;
                  p.push(M(g + p[k + 9] + A + D)), g = T;
                }
                let v = [2059030472, 1729520903, 1677982208, 873419055, 984304912, 3005047866, 2874125293, 2152413264].map((k) => ne(k, h & 31)), U = [[101, 5, 7, 6, 3, 2, 1, 0, 5, 4, 3], [96, 0, 6, 7, 5, 3, 2, 1, 5, 4, 4], [96, 7, 6, 2, 1, 4, 0, 5, 4, 3, 5], [99, 3, 6, 2, 4, 5, 1, 0, 0, 7, 6], [96, 0, 5, 6, 7, 3, 1, 2, 5, 4, 4], [100, 2, 0, 3, 5, 4, 6, 7, 2, 1, 5]][a], R = v.slice();
                U = [[100, 4, 0, 2, 5, 6, 1, 3, 0, 7, 7], [96, 0, 5, 7, 2, 1, 3, 6, 5, 4, 2], [94, 3, 7, 0, 1, 2, 5, 6, 5, 4, 3], [97, 2, 6, 1, 5, 3, 4, 7, 1, 0, 4], [96, 1, 3, 4, 0, 6, 2, 5, 0, 7, 7], [99, 1, 6, 0, 3, 5, 2, 7, 5, 4, 6]][a];
                for (let k = 0; k < U[0]; k += 1) {
                  let T = u + k, b = p[T & 127], A = (R[U[3]] ^ R[U[4]]) & R[U[1]] ^ R[U[3]], D = re(R[U[1]], 26) ^ re(R[U[1]], 21) ^ re(R[U[1]], 7), w = M(b + A + D + x[T & 63] + R[U[5]]), H = re(R[U[2]], 30) ^ re(R[U[2]], 19) ^ re(R[U[2]], 10), O = R[U[2]] & R[U[6]] | (R[U[2]] | R[U[6]]) & R[U[7]], P = M(H + O), q = R[U[9]];
                  R.unshift(R.pop()), R[U[10]] = M(P + w), R[U[8]] = M(q + w);
                }
                let L = S.alloc(32);
                for (let k = 0; k < 8; k += 1) L.writeUInt32BE(M(R[k] + v[k]), k * 4);
                return qi(L.subarray(0, 16), L.subarray(16)).copy(L, 0), S.concat([L.subarray(0, 16), Z(Nt(L.subarray(0, 16)))]);
              }
              const pComponents = { hash: (r) => ht(S.from(r, "hex")).toString("hex"), selector: (q, b, t) => Ce(Ce(Ce(539167016, S.from(q, "hex")), S.from(b, "hex")), Z(t)) >>> 0, md5: (s, q, b, t) => PublicMd5Zi(s, S.from(q, "hex"), S.from(b, "hex"), Z(t), t).subarray(0, 16).toString("hex"), sha: (s, q, b, t) => PublicSha(S.from(q, "hex"), S.from(b, "hex"), Z(t), t, s).subarray(0, 16).toString("hex"), xi: (p, k) => Xi(S.from(p, "hex"), S.from(k, "hex")).toString("hex"), zi: (m, n) => Zi(S.from(m, "hex"), n).map((x) => x.toString("hex")) };
              const third = [{ "selector": 1, "publicScalar": 4021320210, "publicScalarHex": "0xefb07a12", "canonicalFirstKeySlots": ["R3", "F848_8", "R21", "R20", "R18", "R19", "R31", "R17"], "canonicalFirstStateSlots": ["R9", "R15", "R22", "R16", "R5", "F856_8", "F872_8", "F880_8"], "firstBlockInputPermutation": [1, 5, 0, 3, 7, 2, 4, 6], "firstRoundNativeStepsMatch": true, "firstRoundSteps": 929, "all128TableByteReadsProved": true, "paddedBlockKeyHashPermutation": [4, 5, 6, 7, 0, 1, 2, 3], "paddedBlockLengthXorCanonicalIndex": 4 }, { "selector": 4, "publicScalar": 2630496756, "publicScalarHex": "0x9cca31f4", "canonicalFirstKeySlots": ["R3", "F848_8", "R21", "R20", "R18", "R19", "R31", "R17"], "canonicalFirstStateSlots": ["R9", "R15", "R22", "R16", "R5", "F856_8", "F872_8", "F880_8"], "firstBlockInputPermutation": [5, 0, 7, 6, 2, 3, 1, 4], "firstRoundNativeStepsMatch": true, "firstRoundSteps": 929, "all128TableByteReadsProved": true, "paddedBlockKeyHashPermutation": [4, 5, 6, 7, 0, 1, 2, 3], "paddedBlockLengthXorCanonicalIndex": 2 }, { "selector": 7, "publicScalar": 2891847159, "publicScalarHex": "0xac5e15f7", "canonicalFirstKeySlots": ["R3", "F848_8", "R21", "R20", "R18", "R19", "R31", "R17"], "canonicalFirstStateSlots": ["R9", "R15", "R22", "R16", "R5", "F856_8", "F872_8", "F880_8"], "firstBlockInputPermutation": [1, 5, 0, 6, 2, 7, 3, 4], "firstRoundNativeStepsMatch": true, "firstRoundSteps": 929, "all128TableByteReadsProved": true, "paddedBlockKeyHashPermutation": [4, 5, 6, 7, 0, 1, 2, 3], "paddedBlockLengthXorCanonicalIndex": 5 }, { "selector": 10, "publicScalar": 3017238696, "publicScalarHex": "0xb3d768a8", "canonicalFirstKeySlots": ["R3", "F848_8", "R21", "R20", "R18", "R19", "R31", "R17"], "canonicalFirstStateSlots": ["R9", "R15", "R22", "R16", "R5", "F856_8", "F872_8", "F880_8"], "firstBlockInputPermutation": [3, 1, 7, 4, 5, 6, 2, 0], "firstRoundNativeStepsMatch": true, "firstRoundSteps": 929, "all128TableByteReadsProved": true, "paddedBlockKeyHashPermutation": [4, 5, 6, 7, 0, 1, 2, 3], "paddedBlockLengthXorCanonicalIndex": 2 }, { "selector": 13, "publicScalar": 2490211174, "publicScalarHex": "0x946d9b66", "canonicalFirstKeySlots": ["R3", "R6", "R21", "R20", "R18", "R19", "R31", "R22"], "canonicalFirstStateSlots": ["R9", "R15", "R30", "R16", "R5", "F872_8", "F864_8", "F880_8"], "firstBlockInputPermutation": [2, 0, 6, 1, 5, 3, 7, 4], "firstRoundNativeStepsMatch": true, "firstRoundSteps": 924, "all128TableByteReadsProved": true, "paddedBlockKeyHashPermutation": [4, 5, 6, 7, 0, 1, 2, 3], "paddedBlockLengthXorCanonicalIndex": 6 }], literalRows = ["0x87aeea5dab37cd6b", "0x7ff48becb4f54087", "0xb0724c06706bbd5d", "0x1fe5dfb1143e328d", "0x1a2331d00af4f1f2", "0xcaff7131bb1e71ba", "0x33385e1042752218", "0xff01ed65d4a441fb", "0xadb1ec8828c80e8", "0x62475d12f4e06fe7", "0xbd0b238da4fe72"].map(word64), tableData = [[1, ["57bf108bb79db062f9ddb8b34a47bee8dd47f9b3e8b84abe47b8ddb3bef9e84a21d704be0c45e237d74521be37040ce2f29967dc1bfc8fbf99fcf2dcbf671b8f8b5878a5215ee133585e8ba5337821e15e7858a5e18b3321788b5ea52158e13398b9391360db8698b9db981398396086db39b9138698986073269cabbd0a38616d4b5da77a5fab424b5f6da7425d7aab5f5d4ba7ab6d427a5d6d5fa77a4bab424d225327a5cd5c2322cd4d272353a55ccd5322275c4d23a5534dcd27a5225c23292f634a8e30ff724febafd2cbb816ecebb84fd2ecafcb16b8afebd2164feccb07a196bf604fcb45a14f07bf459660cb4f96a1bfcb07456096074fbf60a1cb45cfb0cb3d54bc958fb0bccf3d8fcb5495bccbb03d95cf8f54cbcfbc3d54b0958f5a12ee00969838a112985a00a1ee963898ee1200385aa196ee5a9800961238a1ae95688ff45be01f03c3962e0df0aee0c3f0032ee0960daef096c32eae03e00db91db8f90d8ff6291d8fb9f929b80df68fb81df9f6b9290db8b98ff90d1df629bb20121d6c199b45d6a09210fdabe362a0abd6106292fde3ab92a010e3d662fd7e3a0ad62ace6a443ace7ed6440a2a6ace0a3ad66a7e442a0a7eced62a3a6a44c9cfc70fb8b646ab7496db12c7de230340bc896c39d11109bcd1406c0989391127fcb1b41097dceefc9727b4eeb110dc97b1fcb4dc27ee10b12797b410fcdcee2f1fa44882a8837b1fa82f487ba48283a8a41f48832f7b82a42fa848821f837b5d080e612ce690ad4064f5e2d61184bf641140e2bff5d68411f564e28440bfd6af6a092da885b1fc6a85af2dfc09a8b185096a2db1affca809af852da86ab1fc9a83f80e514f8ab42b252bf22e7ba984257b2bf2842b2ea97b2b25f2a92b842e07db996659c8c80858b35a6e06f8752eb3f8586e2e5a0675f85ab36e75582e064305a207db5bde0b7e70b183208c72a5708c7e83a5b120720f9e0b01d6510d68203e7f6ac375d1563e75206a567fc3d1757f3e6ad12056c37f20756ac33ed156272807b80af5fe4e28f527b84e070afef50728b8fe274e0a0727f5b80a28fe4e4fed85ab7da8c6bceda84fabbc857dc6a885edabc64fbc7d854fa8ab7dedc6bcb128b2297b8444442884b12944b27b4484b2282944b1447bb2b184297b28444448cf2d08f17bc62ccf7b48082c2df1c600ebe3c7bd0024ddeb0000c7dde3bd24a62117040717d6962117a604961707d617172104d6a6960717a617040721d696708facbc161c4dac8f1c70bcacac164db0bac20cf7b2a0e1bab2b00ce1c2f7a04c8e8ad933680bc88e684cd9c88a330b688a8ed90b4cc8338a4c68d9338e0bc8a9a33ec1062a9e51a32aa9c1513e069e2a3ea3c19ea951063ea92ac106a39e51729d67dc99e88d369de872dc3667998de8679ddc8d7236996772e8dc999d8d367f7381ca1bae91a673ae7fcaa6811b91ae8173ca917fa61b817faeca1b7391a6381cf9dd354e42031c4e38dd03f935424ef91cdd42380335f9384edd351c42037df6ed9f583288e2f6327d9fe2ed588832edf69f887de2586cb72931c950fb4ced2a20fb5b3574a02a35edfba0205b7435202afb74eda05b20ed35fb5b2a74a01b0a9f4783ef0ff50aef1b47f59f830fad9c160937c6f67a9cc6ad097a1637f61402c02777dabf5dafd36e316a3663bdd336af31bd6e6a63366ed33163afbd6aad8a8e39cf554f738a55ad39738ecf4f558e8a394fad73cfbbe3173ad3c477ae4ff9ac8e0dd6871af9d64f8e1aac0d87d6acf98e874f1a0dac4fd68e0df9871aa3896a1dd8cbe21689cba31d166ad8e2cb6a891de2a316d86aa3cb1dd889e21606bfa1b94786dc8abf8606b98aa147dc86a1bfb9dc068a472bb900bffe357dcdc5631740ca199fc86319c540c817ca9fc511e907b47cc87507f50ea468ffde106622e623412694649bacc764b860e02bac609b642bc7b8e060c7ac64e09b2bb87d4516d4f0f4cc3de67d17c9e5dd12dab74223d83310516ea006b167cf9a74d78cc97b9826051e0a0c45448fc0e4e30f45e40c8f0f44c0e3e444458fe30c0fc0a177b0d613cf34eb77cfa1d6ebb0133412a2ad6176823320a282126120ad7633a2c4feff892484ffc424a2fffffe898424fec4ff84a2ff89fea224ff89c484ff338221dc5a708740827033dc40215a87702182dc8733405a213370dc5a8287405233fb1b07f29a5633f2521b56fb079af2fb331b9a525607fb52f21b07339a56ef283fbcbde4c16728e4efbc673fbdc1e43f28bcc1ef67bd3fefe4bcbd28c1672da6eba7e3bdc660a1467f557becd05c1ccd92258025f957cd251c25579280f9f7e2888b1599ce63e299f78b638815ce9988e28bcef7631588f7998b15e2ce632339cac5a564ea7a4945a119fdf9e5b0a049e95059f1a41449f1a05014e959a4b2ad0ae1ac711194ad71b2e1940aac11710aade111b294ac0ab271e1acad1194d0527816cf2cc0ab522cd016ab78cfc026d44367ca7d4aded47d2667de43ca4a53d75fb533c40d62d7c453b5625f330dc45fd7b50d5362335f53c4b533d70d6212e987c1f672c953c82cf3f20bd97d6c9f67311a26d2dc7967d29f1a793126dc9a33a9f7deec93a633ec9af7a6a9de939598152b09a90f2998a9952b2915090f2956b7205c66c568f387a21349cfd79b1f76ca00fb79cf4f39405f5f10da21ee76b811151e1a1e76118f5d3c6318113740cf8a23419763eacf974023ea8a4163aca401380679e92be158120f2f0de41b1a77bc6244b555af108400447d603d32966b44e3c7e0616bcd494870fedcd24acf07f4c959ce664a46ad636d4bcc5f1f5b6cb6e3493cc4394d44d0bd9c9711251a326ce5c4e304a8da3e5d1c1b847c4e", "fc59745c25dfeea388c5db4e58b1ab5f10df1b0206f1eba2ee59df7c74a523dc33ee0dfec75ff9ccdc59a5235ff4fc6e79eedfb38dc74c7e025f8622f19b906bacd2f0c599102f3cbcd210aff099452ccc09cc1c30c3dc6dafd210acf019bc45dc09434c4cb0ed9cc5d219bc90702cafced55e059cb039139c09b06d434cccdca5d3d53621bdafaeae53bdaf55a1b6a5a69391a9522e91e6af53bda555a1aeb69113aea691d2e629b653a12ebdd5a5afe6935211ae91a9a6a993d266ae9126912769f6d7658b75dc312547987fb9949783df224bb0e5d0a775698b27f665dcd7d0dfe58322b027cb57e9655c0bf6a7f5a75fb0d0e522cb83cb5fb0a7e5a28350d89ecae7472ade65e51e2adecac767d82d8050774b1c094cde1e2ad8cac7e56709001cad504b4c77e79ec765aa4a58de4c004b099c50772d77004b4c9c502d09011770cb06d761f8b447fa2df00fd74adcfc14dc06fb8ec76117d701f00678cb8e7cfbdc948647dc4b97067857f08161c7fc860efb14dcdcdcfc8647fb94dc0e6b0831c9fe71d055890eb68ccda25d103f6b220515351d675088716bb1fe55491d6b353f221567054988fed571316b50676b151d3522053f056b156735223f1d44b69ce8880420dee3075c5ba3d5e4e7135af758086efecb20b684c49c08de687e5aee137788cb586d8963ef91013acb4b5a087e6ef7d893585a884b6ef713fe0fa4c1973d4154d2522441d4c1bd970f7a71eb08c25f20b25424c18fc13dd21720f1df7a6b42b20817a43d52c1c10fd4327142a05feb887a87301673c8d62e04b596d8577ed4c2048416d4c258fe57b5157997bd54c29592c21654b558fe84d71579c21597d492bdd716fe04d458b5c212f9d4154297bd957c87a827455acd412c37172d83ba597c4cb32c64648483edd8411046b9523fb859b73a2c17037cadbfc1d258103938462d3703fc3a17ac598500eba806b407cfd183ed2def85a1021fb56810abe1ba3f3fb5e1ba682b109f135ca703057f94fa3ab5619f68ab3f90145cff132785fa031035abbfe1689f3a7a5c05147fa78393035c857a7fa71394f655e327de3ed4c2c2d53e5463dea7f6d81422d93d2214c2d4d5be7663dec2279414a258a23d4259a755dec23ee376d4c2943d142222d958d9943d4222a25814f1e35e00926e80f51684f83d6316a4e75302cb8b03eb900b80e3eef15e92750010026b53cb838b8b2404969678e3e73d0b8283106bcb0bd30b82830b6b4bd39061867b59d070585d565e0b8e2656b847a66c64c599054734588670e17b505d59c7ec0526e4193445385e56568ba6470eb4ec19c705644526c5ec19b405642647d160cfd42803159f9f600315cfa8d451396e9bb3ccc64e7495608351cf289f544eee46399b4cf4b3d4e0281f03cf519574eeccce469b333933ee4cf4461bb9ce39e5c83fd30dd7c040e50dd748d3bfb99cee81fc1a210e2757e58db948d3c03f8e6e219c811aa77c3f65d3c08dc839d7a7ee1a0ea1817c1cfcee1a27a1011c8efb4fc43e712c9976f64f2c1944f13efbf67d50902d3a959a949864a87d26b6db957dba76d0ad1a10be4ff1762c447b999afd2d153a5090f690fdad1a3ad076158b841b637bbd564ecfa3c1f787fa0d85b718359bb1ded769d6043d8b1b7b4ee3d7985e37b5b1699b8da3facfc10785f7e998b1d75e351bb7e0933beddf2e0a01c59ca7d6b9e72a47c79ce7aaa7b9564527470dd686c37ceb0b9d69e23bd7ddf17cc7c3278d066bd6d69c39c7e727c5aa6bc786fc430dd62756c706eb438da77cc40ef1510bec65b5b50eec65718bd144835cc5d023ee5f43e50eec44710bb5d1df5c6e03c523c3d0d10e0b356cf1c4e5805fff9abee6955cd0dc23436e4583dff4035a3ee4bae2880b20e58c4fe4e2b163325c30f0954dd60752b47f6f88837a4db295635c7056b06220e40be5cfb18c5632f0cd155cb063f39120134a32331111ec198828b75ba10b6a787ae69ebe22a24760f2f1078622d8b3674dba6b508386c70722e0f122728be4f26e096df3bea2c77186076072a23d4c93020f05c6e4d6303bc1191009d158eb89679af5d03bd1ff7fff4442621289309056bb195141e27f42d1ff44127f50eb75d8099abbe792ff4462c27f7f51ffff4412c27f516241eec319202db810106e2db843a019c1a90dabfd03cd1979386e2dc143a09019990d4d29ab03f9fd196ea010ad4341b8f98d83194dab7d29fd8d03794d2ba99914dee0f7b35ef21f1fde5ef2e0b37794bfaa3d7668ae50a372de5e94e0b39f77c912c092fc2b8e6677deb39fde6014f28e922b49c0fce612f5d3f15e63b016d3f145e7fbb18a4c44c4c58a4ce7b17b71d08cfefc72d8a4a2ccc50a71e731c4fb74a8ac78520ad0a4fbc531c40a67f1cc50288af42cd2a478e5e2523275bd911cd6f008594ad638858570d6b8084ad956688b55bc67602916b870d6d6084a05d9a133e53e256f13ead9704a05d688d6389333ef216525ea3e3c8b6716e0556829ebda8629b119e2afafda19e206b1a9eb79f985ec3e366496e2da99eb06b1af29180d1369eebccfb3a95ab1af99866be24f8dbc1813ee33e9c3607bb9e42989f48a9584d487944accd47b6ff64953cd99d189a4e7ebcdf943ca95948a8407ccd46580fdbce7a70f3bcd7bd354efc91976af2f08ed10f71ca05b102eb362b414abc591a0cb3175a067880a0f0d0f3b3bdc89879706f28d702ca01175c5a0b1e74b5e31a2daaa578d3b2e9e318c889b88c700a23eb01e190842001c83bcf41556d2fae42c6733a5e703a2f163f0b035cb35e85ececb88922622b1b625e6af0fa3d6b672e27102540d1924387f6e69a5e6242e8e0d423e276d9fdbf1241ee29c2d36", "0d0183f8755188ef3aae926ff751fe2cd2912f7a7e37eeac6f3ebad2116ef7acefd9c66326bf3cf76d27acd8d52fc4e24391f84dc835812f06ffe3af7ce619f7660e9861ee36e604f8e24c88171e56690c5e483896d762e90856f80cdea25769af024ed89c09e76a8857f8cc22165e69d8b62126666ece04212626d8764eee84c85429974873d3c96a9b90de57d7d2e95097deead257dba9ded2aa5057dbd7a9a908d7c85453f349ded7aa50db52d7a96933d74893c8d44957d34869f394c8099125d872e8d3c16ffbebb2c53aee933432ae05fbd3faabf4c513fb32eeebbab458e87291e5c1d32f23ccbf5ccacb9892d8d372d141a8e52ff24111d89365e8efa8bb258e04a61640e5f32315ef326c4fe33255252cef73cf156ce5e3f2336f0fa5044ea8bb162680156fe5e333ec720f25264ea896843b808e56a825a6bb04000a6e837dc7636e7eb86583eb30fc800b03bc2bf8c0b0a54beb007803bce5b08b43877d0a6eee637efd16f8876b25da23c3a37d4a6e076e7e7d6e4ac3236e47be91828a9a8eb39f359864ff38e8aa3584ffeab89835a82444b8b558ffaa2428c48a8e1a91829fb3b55bc666d12e8844078ab31a919f8e82b59a1f918ab3828eb57b2c0437ffe509ad4e744402106f225bb1f7c8009de5b6c442624e046f34105b043fb77becc9252daeadd16af2f3f103c425b7fb097f2c2df7893bc4652c3f2d7504e12f1059bdb8e0cb9e202ae907d21ea9e0e007ea0bd2e0c7e01ee90b2a9221d0af75443d993820eae0decb0729928b39646b178243186fbd3521590490f8cb5e2ae14ac98abcec2b3f6a61825a4b7f026aac5ae16b0baa5a2c7fc26b610bea0aa1cbde4a897c6a612cffab5a420bd49322ade620be43e18a4b6ac9de8a3c08a35ca91f5cec208b9641dd2c3e969b017e9d0bd6ac969b1d968b01bed6ac5b755403da83e74280163232c2c176a659f696f7c25081e8c1692c881c1ca3df60d381823f4afd09ae3488d570dd9f8f5ad5df70b44f1d889ab04fb4d51f489dda028abfd3c1493dae705db41588cf9fda42bdbfd309ca01aeff899342fd010aae91ec1e110a616c0af1136f1f6a61fbaa6f619f713bead32a5fbb316fe113ea6a1e0a11916c2c61ca1faa31ef537be16a1e2111512c8a6cca512cd11ea12c4a0ae5c58175c88529812f004937c0faf8714b4bbcf1f31e1202f7782fc93a00c0714188b5e585e905c1fc9e310bd2730b42c185b5a569c805c1b5a9e5c1c5450881b2e2cc82231a5336bd2c6838acae30c32bab45d323071c2fb8f03da8ae2c2c438ce302b222135af60547132bdc232baf0cda023293a362f60213f20c9aa263f6cd59666327ba1cb7676a94818acf68b0948f81e7a84a6a70c1a867944faa4ab06667a3cd991c3a77818a6754eaa84fb0267aa38d5ce71977a39c4d26fa592777407e8d1087134ef7e49fe9866be09c7269e046e49ceb9fb2c65ca469e09fabf20d87d0403e8e5377866ba4e9df5ca0f28d93d0000e477e7710ce408d533e47b728c8169d4a4dfb3e629f38964cbbfd27783b16a2bd4cdfa732d43e13db6d4a4c960a1d28487bcdfe960ca2789f7dfb27560d1d68bb0ac8fe5d3be8560d88ca3e9acd58efebb45b8c8db1bd5e2ba745c2fde7e083c2fbc6519ec58d3da7716b82d86baf9a8ddb74cce0fb43fd86c2e7d19df66f178500f0c9af9bdad8b4cd6b4c066bc361bef593a353ebdc7395a362ce9ce3f39362556bce34f19debeef885ce43fea106eb93b56373d5d35caba263ce83f5a1c6533eab63e1934683356bbee362e811f7afa141aef8a805f6b25a6287851ab678e2f2688776a2b885dae872077f4d5ff34a2ec0aff6b2b8c568a25a079121b7a2c16f68eeb781e29161e86f2e2e18f8ca26eb31192d1f725d7144fa01f285f2e758463110dabf37c441bd0329f8e60a2ed8312b1972c62772f1d80590900925999988f948ca312e382bd826d930f9f8034311d1230c4494dbadd008f679b784b679df4572b326dd35a841ecd938c303303951d1e33c3d734f5f9105354981870263f21ea60311f0781139c3e3bf7f22213189e8ff9de00c8884686b983aec04cddd73a8f548abdd8ca8a044182231e1bfbf28c97fc433cd7ae81dacf52209e1bf28b1ff7fa1e87f22893ff13fd5fe81e68cbcd486e10c90165c8820f75088d6a120dc0c3796e02150c80c1cb7c18ca6d5be94fcc616dc21d08c6008b781bca695d4ccfec6a694d581fcfecc861e3b3457a8d15fd5f0fb592ff90f0a6fd94f6f300af93bef2f4af0d9cf3b396f9524607e730947c92f79f0d93bca0f6f78af31588be9fae96049fe1547b364097f7e396c52516846f3fd584526a2f8a2186285b378e6fde285b8f318e27de662457a1669523c281445a6f3d8bd38e2622999bade488e7271563c290568523a542ade33b0140bb4c5842c256b9c426b78a5026b446b9c6c386b6b04a5826c5c38f790b212759fc9996b5c04a56cab4238330bf02ab4149ec5729f92b709f5d09942761f1b32cbbcfcc394d80cf1d7756dd8d74cc335f154adcc7583d8d71471ed5e8c09f799f4a7460c7183d8d4f557edbd5cf29444fa61b0893477dee7598c86d2f3f5e6fca1e84442ea434a2566c54a69aaf7e40cbbe6bd4a45c203666ae54a8476887b0ed0d71737fba4a9e64ceabd9759315a8ad52d087edef3d3879d32c04b03f9463896c4c3d0e5983ad0b3e2481846c44dc46317cfba62d0d8f325d0881f588f0c042100518786879d1d6e4485415efa0a2b69008e516dd5abc61daf18e76544491311742f96b399d2f3017d723fb7b4527312129c12f3d78751eb58db06219f93b64f17c73178d89ae51ad1f8120f71ce169bed78f13801aa860c5b39", "173dbf1b7756e9c841fcba28c4f7868056ecea1762f1b6135de908b77bd6371ffc26e49ac097a148c9b7fb287f161d57f1573ef38c7b83ffe331935f9efbf76c241ccb6bb174062fcc30771b730233077c66110baf34c42b7c066fd1ab34042b1013333767026cdb26c40b0fab347c71136c3b2777c21013276cce8473b557016f75e9abed54a84b944ba4b9e96464aa55a86da9eb54ef6b55a8abedeb546f696ba44964eaa4b49948efab6be974b54da4b4794ae484ab696b64aaa9f9a4548482fd69fd557a19d76c39f4e9e0b7c8125f2ee5654cc911e67d19f7755ddae289b9e820d4f217ec69d9621df7499afd7508ecc932f477f9a0b9c8f2e0e9172c74aa1296f7b9e77199124702530b20d4ddf2f11976b9878ab7f271f999b7870ab627544bc21dc01213918a7719b6a7f2f9d412d35d0200472b27d45d0b13c05202157c60d8d2a501dec1bee331373f05b7fcc3b512ed917e0bbc01de72d8c575003e25b70337bfe1d1c175187ec005dcb2a5e111b723df3e373e0537f731bfa1c35ccc1a5412a27f75454dc7d9cf9a4841b3681744a2832d63ac7f55121462dc5a8dc84f47c15ac5597f1c74d51a424cb248c55941c75acd8f8d48c1cfd95a45476480ce725be2d87b829bfff284d63d166835f9f9f801d7d62782371a882d2131dbfd843f9616e29222018837912d273a1de232969f96fbc4db3df6e49216829f70f003f505698f54f01788ac5edc3a8270efe58314491075708ff4051549f063b2b50bc1218cc51c4f1095f40369f0659a902c0248fcb7ded73aa29e4c9c10e83556adf0b5853f019570a56445de652f96ff552da105b530963fe1b5b005552d91567310df21ea491fb53041ad25f69525b5646f459e70c5d0656fa5443e7585ce056b56cbcd00bfaed40f2e7610845119e1603bd32c0b19c5005f6bd6ad0ecb7b61a840f4607bcba06e161fcbcd45cb440e8ed16fb0341601edc17321c03aaa38daa70e44cdea6fc11fa5fe04d7e940da0ac4e74f6db82edaea0fa44e6dd827dfe904e50057a1de6ab8eecf472d1ac449a1fe0005d7ffc4dfe9e0a41e5701c5cfb81df56995b7b08f0885303685487698f7a9bd70b50fd598b7f00975b5afdd8828164536658f90b70fb5b07dd5f889688f5016258528968848369630650f85def8790f0981a525c03ae4c294c0f2e29805e9b905217ecf97641d00e0b87bbcdad234e482e0e0c2a41b607dfcb81780f2e0e22284c0dad4daf2c2f482e020c4a2e991038e9795d566c1118d291b59718915ee9195d782a31e54571696215cf80199c951317b066d341c565798e15e1679064dd1317b8109015991092d7bc671c07354253538cac7b3b1135d8edbe62c332a75d427d840c533ca275525d860d4d146aef38c3b13bdca40c56734d833352613fdac93bb51ced1e64c0e9d3bb3b32372cef54fd934704688c309a77b20bfd2f46f2e5079c335d234f0cf5579632e68008723bfbbc64974c335704e39f2cfa0c6299fa35b086768201fc7a9bb86430bd15ea6ef53bc1d8b4ea5a67d1f146451bccfbefd134b069f89ed362526196a0eb45d05647fab861c4ba6ddfe13b14f74ab0644659fae1d0e14a4bd667f4b85f041e17de3a8fe73acf775da2d46cd66a17e43e1f368f0fdc69ed3b83541cfe2b78b4200f8e44efb5eaf95d322e1c6d86d6cdae635a6d74d57cdc66d3a66ecb5f949b1aa3567cef1e130dffac95183b569ae55d131e7b9eace7577fc42679af850e3299fd5b1c1faeeb9ca5131e7a975a3c19a35dff1f0495083f5c9dab121ff5b3c7179b4c3420d88fbd7d0205731f4dc623451ad037b59dc426d74b9033b515bd1e03734f7c890027b592db1437cd4f1c830f43797db40af792517e0d7bfa6f9732ca31808f9427c6593f5980c170c13b978ec024839e31be2a0de8114eddf92cc4cc47c24c884b9ae3822fd80960f179c156c936ce5180517ec98950c7c7342dbbcef22b9bc5bfc81a188e811987cb9a7afc8821a9e9eee1ad420f6ec5993438131790fd3a4c0caed5668047b062278bc889ce1f1810801989ca8e8719ce182e6ee39d47a1d7691909844f4ffdf3f663df40ed67ae2996e465450220ca4d5f05f94d8ff3f9184064442b435cc4e703f91c49ff89f50f4f0df5f94e43f9198eb50106e861b28444073465e6ac36aff10684630845b0bee102864068e5b4bf0d34a6a667fe3405e480b2e4490fb7006ea407e7f664353cad36a5f4a7ee36046371885fc9df7eca79a2bd4e8af6a8f1df8ec1de587b7973cf8ece79d9cb7172518acc574fd74bcd7ac97fc078537f8fdff8aa359b204b02430bfb984a3e44a12c2593cf37e710cb11c36a92834a33fbf79ec5e1c71b122d3790cf13e73b142dc5d6f2447b9b8944cac2213517cd1f97e940234291d2a2b9e8b34291e148a223d35a2354e369c528119588a05da6215ef8252b655219c352e825241362e9cb53578155a0acfe2990592354ea1353c4296c9db847ae84cb94f5989bacfe4cc7b48a6e19a78aa56ec6b8f0d99655e7e21bb416ceafaab7686b841ec6b8ab876e6ba794a22fd30d85e2e6c86f8ebbab6614a3beff32c46c3449a84fb4cfa53232fc67b72865df3de34d57a73fe507422e9f9d2547326f5de9b7de10133b57225a522182dc5ea1684cbac21a512b3622521f5f9e9c34e19603fefc43d07e8eb0b423be226e2b18b670c237c231c4be2e1a581c3ce0e37a2c243c368ecf91268445d317d85953400c7202f4c1de8597124e872ea55e38e578ca8b64706821080a80fac5aa9390909ce9f5ba2a48908ba97f3326ccd728d68fc183cebc3a875ac6d89f938678bcd763c89874ce9f9803e39cbd900554386ad9c789ccf49dba78b638390", "f50bb178db092b76df8d3bab74e48b9e7d943f8b8eabe4db84db3deb9b8fae749f79c6bdc1fff82b5d14e27b43c0207ec92fcffd7bb6f198724de0cb50247e138885571ae2153eb3e5b5583a8317128e8587551abe3813e2b7e8551a82153e839d933b61888909b6bb8d39819903669867c2b9daab801336999b3301b66d8889b6d475aaf7b52ad4f4d5762ad4a5b7bad5b574bada26a4f7d5f675aab7b42ad43c2572c2d53452dad2dc74323255ca25d5d47c522ac2353224327552dacc35d2f232a6e408f32f97b4fe2abd8c6bc1fe8efb24cdfeba6cb1fbba2e6df1c4be8c6419fabb7c5004f6fa74f05b6409b61c79f0f40b16ba5c64106af90bf6b45c740cbbdc43c55bf9f8cbfbdcf3b84c5509bb0cdb53f9fc48c5fcccdb43055bf9b8e92e0180a3156a8981a90510ea6e8923ae850960298113ea25e10e60898913aa5a89f648bf05fee1306ce9d200ef0a3e0c3fe0026ed9e03a6f39ece23a00de0088db916f9f9bd2f0f1989b9f82db60df9bfb98dfd0619f82db819bdff0689f920b22d1c196b159b40d2a09d1bf3a2e66ba6a0d2126d93f0e2a090a316e2dd6bfaca063ade647a4e2e3ec674da4a0a2a6e0e76cada2a346a4a7a360ade2ac46e4fc7cfc806b6bb49a67b92d71ec3d3240c49bc896131d91001b0dc496909813c119cb4fcb7de20e717f7942eb1e0bc1cd7b72490bc1cfed1ec21f4b0b71c9ed7ef2418a24883ab8f781fa82b4472a38f84afa8134f8b22788fa828a24f831b847160124fe5b6f4d4844562f6e1d41f80b514f264e08f46b1d85e010c6620ed9daaa96d0825a18cbff56f8dac29f801aab98a0d612fbca8f5af05ad882aa16cb9fb2b7224fb8e2925a52b222efb2974ab8b752229fba42e8b23988ef10f5a448abb09d6996858c8c7035abe566805fe7828b8fe5e6a2655037af35eb5687e56280c7e837581a0b220707173b08c22857eae0b910601dd580f654207ab0bde5bd30e2f3a7365c176d055307a266f5371cedf7e7a3160d62355c0752a736ec136df57f8082eb7fe2a450527f82eb74a0e08f70528fab80e2ef74827280ab50efef74d45eb8da876accfb8efab4ca5bd867dc5ad8be6afcc4db87f884badad76ecc5b288b9242144bb44742189b4224bb47841b4b98b2874244248b229bb247484414f4dc8210bf67cc82bc8784c0d2126ffcb03e7edc0b40d20d0e0070dc3dde4bb2711142606d6a797072614a607971601d617a417010626d791a72417070616d69f7c8ca6bc1d1c40ac801c7cbca6ad1f4ab2bcc702f0b1a0e2b0bcb102e7c0faaa6e898bdc0843c8388c6948dac38b3e0c884963de3b880ace4a8983d83b680cc3aea136ca0e21995aa921a1ce563e039e2331aec991a65a093aa126c30ea19e57ed6c9dd28679389892ec76d7396d9d82687ce9dd9d96873d779c69d89de68233717a8bce11a69fae7faa76c1ab811391a38a71cf967bae1f8e7aabc3117691a94cfd12d843350e3e184d33d905f23c48fe3d45dc3213490c391df5de324348067dffe89258328de2fd3f729de8e8568d36eff89d8278e25769b12930cb5cfc403a2b24fd70eba5552d3be0f0ab245a7d25eb3bfa542070aae02b2bf554307daa1f07934f8fe50bff0be7154ff39f8a0ca699170636cafd769dc9aa0677163cf6df31ad3eba636363aed16a36633d6fbe3361d33f6daab6621007c72a7fddb45aae898f35cf534d758d59a33e7f8fca4e5a898f3d43af75c3b7ea1334d7ce7bacd9aef78f8a4d1606ffde4a8c1da7098fa64edd8907fa8c194cfead8607da8f19aa8d681bd2c6e31b83cda61a1862d9eac96d8213e6a81bd36badc819d286ea118fa9bcb6da078646b6890ab187ac4fd920bf0eb5fd3d7bcf01b9a7b64c8ad683c7601a49cf1895c96510c847ca1fc391c917e40cb875c5750ef408af6ef0d710ab649b6728c0bcec97a4c860b06beb276cc4a06beb9820b26623e12644249665764410d4fcfdcd3de77915cde2da16d2b34823d0311e5766a107bf6ac49770d44cef0f840043c5e5044f4084c3efec04e54f438cef0004c98bc876952e0a1c07a076b3df14cb31ef71c6abd0e3b417321da1a66273803222a281106d26a3723e24ffc4f28fa9f484c22faffef9f48482f4af29f484cf8ef4aecff9f4842f82f2318c2ad057708340837c30d14a275281722c87d3803a4053203c7ad25780814bf3fb3a129657520232fb561b57fa0392f25bf7130a369b535b3bf7120af69258ef2c3db4b1e7cf642fece7bf6d31b8cfe83c21bfc7ed64bf34ecedb8b127cf6d12c590258927fc56af457b5c70ecd155cc25172250998df62ba7e3ade6b0cd62f8eb85891e93c769e79bf388658e12c8928bee87c3f5691789fb95821ee3c869a940e95154f4a0154149ad19f5f0e9b140f0a45919e459a92a35c5c4aa6ae37dbaa10ce1a1741291a271b4ea9c01ad1a7d01a1e214bc91a201b17ceda1a41a9423d74a6dca7e46dc5026db18af70c2cdd6772e63da4ac442d8567f1cc02bc0a75fd553b43dc20364d3c552bf635d370fc755ddb3025364335455c3b73dd20f67916a36122cd9df7cc322fbf90ddc78626fda9911763c27d917e186c2f973c2539937aefcd3e69aac3ae796f9aea3d398959b19290fa9052995ab9925291f08061a70cb09ff7fcf47f283a91f47cbd3903f4f505a11de29e62750bc265568c96871b51e1a1e16167f1d8c53386117113f4ac38127439a60e7c0934a2ae1834f671c72b46545bf5aa8e25f1f0d240be11410840d407d623034a1a80639097bec2b946347e0c1eb6669c8404e7cf2dadd47c409f9ce56ca6f4d43ad6b6c4fcf56121c3564e3c4e80aa4404ddcb791951d2edd3c5b141c8e7a4c5663b9ec4439cb3", "9f45c755f2ed3eca58bced8415bbfa85f1bd216010bf2e0a9ef5cd47573ac2ede7fe3ddb78cce4979d553af245cfefc6f0652812bf09b926e3dee07ffc95cf3c2a0d5f9c09f1c2c32b0df10a9f59c4c29cc0cc0133ccddc62a0dc10a9fc15bf45ced55c0099b33e12c9dc10b09c7f25a9900db36c4c4cccd9d30c4c404dbcec93a5d6d13d2fbea5a3ad5fb5a156a5bea3a19992ae512696e3ad55b5a15ea6afb3e2915e11a996a6a3b15ead25b5dfa6a3a296de61a69129939e16a1a296d9e1292667f5db658c77d537284f9974b7919f82db2045b0e7d3a97b678625fc67d5dfa050b5d2eb23c78955ec6b5607f5a7ffc057b5a2e3a08b5fd5d3e28027bb20ceda97c7ea4e25d86eea1e2ad7c7c865d020875b7c491c0d4eda182ad7c5c7ee604b094c00975d7c2ee795ca6aa84e57d07b0c4c409d5927000c0d10ab5c474977001b76c701d861f7ba4df02ff70ad44cd4fc16db0ef78cc76711d006f80b71ccc6fe8b04fc1cd7d74698077051f18b6cd6f78b44fc9edc0c8b7cf4d6978c4ed861093ec1f075db5e860cbd82cda0591b326525051d371f68518b716eb5f9504b656d1512352f07384e85f1d17b30695b056715623f2d351b156f323527156d064cb898e4800e24d7ec0b5355a4d7e3ea1758f85e0e6bf3c624b48cc89e08d06a485e0e7768f3db99638f61e19a0b3dca585b8e4763fe18fa7e53e7187b88ce5401a7cd9134425fd4512441ddc7bf92017b78e20fc0522ab4512fc18dc237d41132704fab58ea82741da23151cfc407d086331876ced427012ffadb726248b006b897de5472d4c5068412d8ce57f554b9177d94b255c29596c41558be54f782d914f5d2174d95b296de14f408d552b7c77887a52a4d51cc491275c71492dd95b7273d132a89bc5c734cb42464638d8ce1d0461942bf5838b75abc37231c0d79a08b08e6a407bf05c7233c0af73c19ad53dd8def25e182a101b2c8d05918363f4518b06b11aaefbf3531bae8bb602f1f9c1753a50f047a93f531bf689b6fa03a9c75540f1773a38a951b3fa1b8ef6a903c055a8f7773a4139c1f53f7152a83f405f357ee2ed432d6c5ced4335e67d6a2f4d2192dd2342218c5ded6b37e62d7c424cd9432122928d255ae52dec336e477d4dd92324228a459149218a25da2394453fee0520e906581f4188df3366417a6e25b0bc38b00eb93038ee1eef25590700203808b1b6bc30bd42606989377ede432038b8b0b6340db921b036b53cb8b80866b897050d87d515e5b5e06862857b64ca46569c59704463650817be07d59585cb9e715c40566442e36565b5687ae480cc9e415b40667254cc5e60429e4153740df64c8d3250f119093650f18c4a1df5e3b639cb6cec4497093618f58cf24955e7ceec6cb43993430d8ef231f01c5549e3ce446fb491eb3ce46e94b3c9443feb538efc33dd700d9c54de708d34fd9b0be91ec8af11e270c255de988b340dfc73eaaee1101ac8c77153360ddc889c73fdefae71121ac0e1c8e816c219a871cae7ff44ec13c79269b7ffc4924114efb36fdf0705d9a253a969894986da6762bb4dd9df52a1030569affb146fc742b497e9d9dfaaa1036d5701d9a76b07ddaa015148b831b6d76be5b43c1a7c7fa8df50f88b51b319eb7d9d764dd0b3b8b1e7346e8e197bed55b3719b38aaff1c7c5078df3eb9d3feeda210008de975531b9bb679cc796a9d7bae7254cc79ae7a9a6b557472d4606d38ccb77ed09926be73dd1dbf766cc83fd4607db2cd99737c7e52ac6a756cb03ed478ca67773c7cd268b066cdec101fb5c05e564bebc05e16b7184d54c8550c3de2fe3534eec04e14b7501b5df8f5afe96b5ec905edb050c3164f5c1ecd3d32e45634f80dcde536503c320cfd3fa0e543ae2b8e480052cef8442e1ebb26c305035fd9643d2045fbf78638a8772503df5cc1053b660642be50fe1ccb281f0932a124331331245b39c6056705dbc19e818872bb151aa086a767eee92bb27a04261f7f6028223d7bd6a4bb0635887a1c67780026272a482eef96d036efbbc33429f050604cde787c20021e2f22670db3139c0191106db59e78a6590fbd83fdfff74f24242611080369b59b111594f94f2426fcf71725b55e879da0b97b0eff4f2421fc1725f6fe2714fd4f24f127e43e9c01d2820b11e1d6823b049a110cdab0da3fd09c9197e3d6123c040a9981df3898d1b4da9792e1060ad13a14849bdf3890d7b4929ad9d9d094b23a90df9fe10d7e3feb25ff41e1ed250f3e7b47f9abda6387e60a35fae7ed45093efb792728b99204cc6f2ee1e73dfbe90d46217f3f1def35066b315d2c012cc9bfe268965f74be1fabc844145cacc8741ebb1747cde8cf2f874d2a0a5cac10771e43bccf85a248cf224d8a075f1c43ac7016cfbc2e2e2553d71bc95187ca8a27a5004d4a0d8f90a5648d536808678d8ba0946d55b658c57b069662810b676d8da054908d39f31e5256a2ee330da754608d688d93b37866015e8596c23a53ee53f236a11eae6d98129b21febaaa9d216e109bbafe975fc8ee63436699ae9db96e10fb9a22d4c88b31e13e93feaa15fb9a69b8269e0cb6974b9e92483fd13091e6cefb3c8b5849487d48a9c4acbdf7669f34d59c499d487abede9c3f145c49a94878c04cadfa82d00e71cf01fabc374df59e9c61d705e1322b464bb1ba06d8cf7b7efab0531c09ba1c53077a56a8f0d0f0b0b3c38d78786920df08c7921a51570c1a7bbe0420ea03eb91812004e219c388b88978ecc031c84b5f61250d1523aaad7ad5b8e34fce7236537a3ea01a3f060f5bb35c23eee5bc8c286922826b5b62fefa306a1de2d820e473d2f6e982f3e796566a4e421d4fe221ced962b32b271e2740d59061", "1030885f1785f8dee32af9761fe5cfa21df9a2e777e3ce2ae6a32b1de176cffa1489df845c13f83276c28a5dfd422cdef03ffeca679e716f9e6d3c66f2cb73ffe68019e66e634e602fce8478e1619586e0858463792d96ce6085cfe02d7a95866d1b6262e6e64c807885cf2c62e195866262826de7e44e182ae084cd9970aef64c95728934379d8cb609e97d752d9dae75e9ad2e7db59d0a2dad0a75b57d9dea36738d34894c9d947dad0ab52d759dea358d94364f899c708a708d4c35359f9459822d873e1dfc16bf2e5bace33e49b3e35ab03fadbf4a2f3cb12fe3beae4b5b3d2d171d845afe82c2fccba5bc8c29391f14813d5986fe2e852e17591e3cfd82ba5be248606a01843e3f52f12ec3f6542e5355c2f23ef73cc1563e2e3ff3f65062e2846a49b80358f1563e3ec32ef75068855a62ba4b00e04ae084ba6b610258e036d8773ce6e6a75b36b80ec30fb880c0bb820f0c5bba340e8037c05b0ebbb83cdaa7e476e0e6376f817fb856a23dd2e7a6343ce276e4db74d8a7e0e63ee63729a8a8e938fb591349f68f83ae5a4388af8e8b59834a42f45b8bf5af4a82428c38ab11f9e92858ab656c16ed824874b0f911a9382be858abe8a81129f8395babc74270f35f9ed0ba44472400f126b2e57b8f0cd0596e4b1c24e644f04603b1255c72bb9ff0c7d242da1aad263f1f3fe09fb8435cc6f2d372f073bbc79e5cd2424710fe0291d58b5bbeec09a2927e200d910a0e7ea0be20ed7e0cee91bea022099843b676213884b1a20eeebd7c902209d65b1392450089ff02fd5a47d4938913eca512ae94acc8bbbef2a31626a8b5c427a0c6aa15beb6f0aac5f227bc16b6a03d29d26a0ee23b4416c6f2bfaa25b4a0aeb8a496ecadc813ae10baecad94c8a730ca95fac1c50e826819d4cde263b9b9e0d7b960cd6ab91961b918e06bcdbad56f792f0c15881e6c2123231c6c679a65c682c8c131fa0d964735a03d782e04581d28f8a3d49fe03a83580dd7fdf9a845fd0d47fbd481a859fb445bfd81d4a90dd4fb3b9da01ce02ad7455b81f8fca90d9f3829d41fa0e0faa0f83b1d9cd4e32ac9ee11a110c6a6103ff1f6a116b6af1a16f619b7a33eadf2b51bf3163ea1aef6111211c5a2c8a6eca11af33eb517aef6c512ed11caa2a410a11011c9c612a6ec5e1c58875c98125802907403ac8f1ff7b4c41b3fef2121b08ff792ac03001c775c585b9a865c101cef19b3203db720c49b5a1e5c5c84105884585b5e985e101c2bce2c38a2316523cb8286c3ea0a33dcb25a343d72c0f1b20bdf83eacac23284a02d2033392a66cf7034b1c23db2f25a3021cfa0293a662f382e202b32a165cf9c653676a2cb71dba64619a8f88c067bf918788eaaa406478c7a46f9a4aa041ba237dac8759e7167a87846a58efa041bcad964a29f7572377636da9cc9a17367e4d7087138e1740ffe996eb806ce2947066e44ceb9fe299bcc459a06feb92a6f38090de070e477d7b8469afecd052a6fe10cd438e573740b70080de4e33875d7826cd1a9d4b4ef83f68963c9b4db7f22b76321dacbf47d8a43ed33b1dda6c424d5d081b6ab80ec6fc9208af7d9b77f62b5836ed580a8ecd3a9d08182b4d7ec6fd98cf5be4ebbc5a818dbebb5725a24dc7f0e3e28bc6f1cd559dcd8731ab726e869ff765108009fdcbe3fd46f287c1e0dbaa98d4ddbbcc6f4bdf6aad9b84dc78cb0361ce65b3f396ab5ce3d57392ae63c393e3f2956b5e6cc13dfb9ee8e5fe84c581f6a3ce5b33a36573dcdb52a3ae63c3e693458b3e63b1ee41f6ab03e593b36861e71ff1a1ae42a8f5a602fab257688a8618b272e8f7658278a5ba88d2e776019722b1afc86e61e2f8b5b8c26aa75601b281e1986fee672d7f435afe402fcfa8281af6cb21e93e1f221d71547a41fd05f287f8e65140321fd7b431cd43b90a29950929989988f04677c22178f5d00291ce382b3826d92ad6faee0821db39281938f3f3014113d024044b9dd0a8d60cf774b689bf75d24976bd25d831ac49e3d1478283026ef619ad333f7f4155950c310018f1791333c3e333c009313153d8efb2712129388feff09ce804888b686d9c34ed0dc3d875aafb4dacd880a4a84819210fe8b12fbff273cd3ac87dec15a4f8afe2792f813ff131213fefb8b92fc27ed1f68cec84b6d58ce0069c18508721f85681d0ac2cd7003091e0285ccc0716bc86b5a49cdec6f1cc11d02cd0886706b4a591dc8efcf6c68cc685aed4bc96f1cb14373851afd55edbf9ff592ffa0f006fdf406a390bff39ea2049ffdbc93f3f6f71a83b598ae9f8e92079fbda3fcf0f696e45f71344b96004902e6379770945ce797c326158566f4df8f5564228a2f3a2156388b67de2f8e883b8f21de672e5692a9eb8de4281797643a8fdd8b232e56c593528026a54365a4679126c5834251e23d034bb1405bacc852b2c629b486472ab046b4c6c98653b646502ac8c685b3b300af424be1593cc64550cab62a84b3f729799b500f9d290f292b51f7999c7964f7b121b3cccb2f4c89cd107f5dd7367dcd345c134fd58a5c37887d4d11d7cecb254f49a41f06db1037884d5d7fd5ce4873e77d9ec56898c598709f497f6ae43d5f6fce1f8a4e24a43ea4546256ac24a67a4fceb06bde9b54243c60a656aea49915a3a558dd8270b34f9a6acea4de7be73d3f7dd82903ec6887b8e7007d7d4134906f8463493cbc5d8ea9033d2b8e046144dc443c76f18c2b068d3d5f028da8e4a5afb09206e0186878d8d9e1465478d556bd6adcf18a1181f5c840100210f55e4694341141f772399b293d1fd02767734b2b352721c1f9317f7d18b58eb52df110e76cb1d98e278387ad59ae118d1f8f13a06ac8b0951310f23969fb74716c", "d1f3bb7167958e7cc4af8b427c6f0818c5ae7e21166f3b61958e70bb677df3d17fe533cfb837f81f7cbb8ff267d171951e33f9e5b97fcf366f42ae097c198ac4c2b1bc164b67f0420c73b731273073c06716b1f04a43bcc267f016bd4a43b0c2c1b67372270c313142bcf0b04ac31767c2e64c38577b15703131737326c0b60d5697beda4e85baf4b9449a9b4e46a64a85da96ba4ef5be5685badabe4ef596564a9ba7444eb89a46f4beba964e57db8446a69a9a4f4a45b8469a44a64e4a9bb9d89fd65fa597712d96439f0e7e8b2cc1e5525ec6941c61fe97715fd7a52d9ed8c09e2c437f970f8a2dd6719fa4d95f978b2c0f9e7ec142978b0e422d7fc19e962a61799f7b1e97a9712430b50042dd2d1f9f61977ba8782b1f979f797ba8602b2d31dd250070b442a97897617b2a9f1f42ddb530012c257042b524dc012c3171c107862d5d1ae05dec3b1e73f353701b3f5c2bd11ee9b7c01be02d875d5c07c01a1e713bf2ed73535c87e1075cc02d1b5370731ff31b3aec53723b70f31b1eedc5ac412521fa57c7d4749cfdac8914548b7641243ad83236fa57254121c6adc5549c1574acd5fc88c74157ad21c424fb8814fc9cad5574d488fc7414ac559cd506e82cb7258ebd47b8f92f4f68dd632156939f8f1f706d8d2278a381d8121273212e63f969b94fdc12807813d972a223dd634f2e6921f8b9dd4ff86369212eb9073f505f90f648057f81c8eac5ad2308f75e3e4891045107f7485f5091043f0609c92280c47febad0451493f90065ff6ad23eac9c409817e5bbb101cc258cc2163d50a5f5bf8135009574a56e45df652f95fd5125a500b63f9135e0b5b50d562524bf656e409575c510b13d45a625ff95df6564ae4535708693507f11da29e145cb066b5dc0cf0eb4afde062074118e5110eb633cdb290910cf0b566ddeab05ce4e018fd064b6341ea66f1b1dc5cb40cd01e3c1702aca31a17860a440fb6b7bca37dea40d4acfe86fc51ea4f709d0e14ad407cfed486eba2adfe40ead4867da214ea0f5070fd4f9c86ebfe7cd4a241ac9d0e4eea711550fc9d4e500e7015eafd8cdb519f56790bfb88500863538864f7799fda0b57fb508d790b9f5057fbda8df608655152886289fb500bdb578d9f788864630953f650888862516453f608898d9ff79010585ae2ac432e4c092c2f0e59909e5b10e2f78c49d601008ebbc77b0f2e2e4208ac4d2dba01d6c78f7b01482d2f4c2f080e42ac2d4d432e080e2eac9a1e39e07859592d161cd198b291156758e11e59792d389a4175656119c285ef67d0141db3179890c361758519ee6541901599d0b2671c1790991c15b367d0163c47555283a37c0c1b3bd1e5b86dce32a352477d820d543ca37c5255820d463d32d1cf3ab91be56c0c547c46833d53a36dcee4d0b9333b1b6de43acfb833d11b22e75cff944d033784389c70ba07f26b4dffe60295375c234d03ff5c9537e6226a9cf239ba857006375c03e79423ff4c06f2719cba6b3884067038f2bb6b9c8410ed65fa3ec5dbb1e8546adaf74141b6c5fbecdb3fb1641099d86e536292a1f6b76a4054f6e9da41b164daed3f11fbc44041da6bf6b754e840db5540f6b76ae81f14de378eea3f077a5fa7dd62d46cc6ea37143e8f06df1fec398d5b13f42c6ec6a66d5e637addd4f55a392d126e8cedd56cdca663c65e7bbb2804804feeb47f9f14ab5a73e61c9f0ef3ad9f1c35581be65a151d739eab9e5c77c72f74a689ef1aac59f31d0f9f349eab1c15739e5ae735589fac1d1bf20f359ef2591d1bac0fc51397473b2cd4b0b87f0d0d7215438f2d4613d53ab097c52dd446973bb013c58f0c437f73b90d14b097d5123bc4472d9a5772017efd6bfa150d7e43738f0cb93fc7328a81902f945736598fc970c1c0918bc72e8094333e210eea1d48d1febdc159c136c9568e71eb8a23d20f68f99070c18e59c9c03757c9cc44cc47824c28b4cdfb2e92cbbb251f188a881e81c9c77bfa8a2ca8e1e999ae410d62cf9e35e9c78bc8191e1f8880dc6e8546b06720a280c9898a1ec7191e141893f7304d0a3c68ee9e43add7612709894944fffffd13d643ef60ad279e6966440525c2405aed1349fc89ff0945ff4024445bc3ec0467fffd4549fe138909ff4589fdff1349080e05e166b88142b43467e4a536acf60f81660443b8b5e00e814266e0b8b5040f0ee4f7673634a5acb4e04204b90f6780adf6a5e4370e6634ada466f6370ee4358351c8df79cf7e7ab9428dfeaaf6d8a1cfde517e787bc983cf7edec9797b5182af389a254b004bf27ac97f507883dfcff39b4b384aae2401c15a4cd74fc77b8d9cc533ef17c7102b61938a4233faf3cbc7eec511172b329dc710ef33172bc49d294093d2a1b2e2492a3211c5179defc74893e241a128d2b3f54672948b4bc9d4235ae364c329155881a558a02d56f19e28655b15c259e322281564e3c2595b23bc4da887ce94fb9459e3145ac323642995a8fb4ccebc879457a1a5f02c9e59801aae89a76ac5be66d89059e6e517b2fbc4a6aebf6a67881bc4bea6886b67ae1bf33ecf62344ca4b96688bfae6b1ba6c4b8cfa43f35f2624ca724d20f83ede5922767d835ef4d53bd37e70f4527929eaf4d356752efbdd9271e30532b57522a129f3eec9401f6f39e522a312b5612521fdc7380bebe20b443d152ac6e41b8cc8a6e221ebb78c6302237c2b1241e5e1ac8ecec70232a3c343cc69e2f8146d415835e35ee78c5886aabd4819e1547822ec76420080188fac07a57584903700cf2d2959a9390e0fcb9a54a9a88a07b392f23d62cd788c68fc1c33e8c5ac7da9698bf503564d8ca89c709949e0fe893b39ccd9cb47dba383608f973b6d86cc7937888"]], [4, ["d5ef04e2ed672c987e772eec92d1af3ad17e3aaf2eec7792ecd192773aaf7e2e771c3a098541d627417727d63a091c850941851c27d6773aa19bd6a6176b7b886fa0d64d142e4b721466f70a006ae163cc03089a7f65c6d665ccd6c6089a037f419ab68d08879793ca55bddcc499fcffb726886e510dc7b30db7b3c7886e26519da83d4d8c554774934b118beb8ba0164745d0a88b8834aa63cc0a2297ed9523d7eaff8d51fb4ecbfbd7cb4eff8dea518dfb51eacb4ed7ff4e8dffd751eafbcba587a4a28a37e0be37a5bee0a4a2878aa2378a87bee0a5a4e0a2a4a58a8737beb36b921c76b435af101625b2a5a2d81da2101dd825b216a5b2a2a5161dd810252792ef1c9b6e0b666e27660bef1c929b1c6e9b92660b27ef0b1cef279b926e66996f2a227bb3df04b39904df2a226f7b22b37b6f04df992adf222a997b6fb304c21c2bd56c030afa03c2fa0a2bd51c6c3a1ff772f16cac0c6c3a0cacf7721ff1bc0d85916fab285cabbc5c2885910d6f91ab6f0d5c28bc85289185bc6f0dab5c473ebb06ba47b167474767b1bb063eba0647ba3e67b147bbb106bb47ba3e47674086cd41d3bfdea9bf40a9decd4186d341bfd386a9de40cdde41cd40d386bfa928632bb911710ad97128d90a2bb96311b9711163d90a282b0ab92b28116371d9ff32b146f14eeaf44efff4eab14632f1464ef132f4eaffb1ea46b1fff1324ef4a6dea079305296fc52a6fc96a079de30491b2bf5099f39999f4999392bf51b09ccb2ca25c1616a2d61cc2d6aca25b2c12561c1b22d6accca6a25caccc1b2612dae57dabc252e8c3c2eae3c8cdabc5725bc2e25573c8caeda8cbcdaae25572e3ce0507ebbece20fcee2e0ce0f7ebb50ec616e508a602ab75016edfe6ddc36b4ce181073fbd1dceff1f9a4dfca24c79c7f064b1eb1719d7e98a49f073787886084ca2f496ab49e6b4bed319ab7a69bd6109bed10d69ab731a6466202eedaf22a0640aac77ae7cf7941cf404179c77aaae77acfe7aa417940c7797ac740e7aacf414d3d6cc9b789fd03894d03fd6cc93db7c989b73d03fd4d6cfdc96c4db73d8903b5280cfe025a8ebd5ab5bd8e0cfe2802fe5a0228bd8eb50c8efe0cb502285abd810da610e8b1a7e9b181e9a7a6100de810b1e80de9a781a6a710a681e80db1e9ec5d7d93e2e179ace1ecac797d935de291bb6ce0f6cc51f3cc91f3516ce0bbf61209740600358d8025b4016579b7e0ecb50db65d8068126968b56912b65d0d80385f38a6f4c88f13485001e6501336e61348e63601e65050e6135050e6364801e31d1d3cd3dc4c8bdce38b4c1d3c1dd33cdcd31d8b4ce31d4c3c1de3d31ddc8b3af4dca6488f98088f3a0898dca6f448a68f48f408983adc98a6dc3a48f48f08cfcc91071bfc1a05fccf051a9107cc1b07fc1bcc051acf911a0791cf1bccfc05f306262f648d625b8df35b62262f06642f8d64065b62f326622f26f364068d5b22d709b909417ad14122d17a09b9d709b94109d7d17a22097ab9092209d741d15d2dff46b372c9e5725de5c9ff462db34672b32de5c95dff883c2e1c91fc08ec9af622ce09e09e3ae09a3a9e22cef609cee009f63a9e9a229ece229a09f6e03a2aff87f152805d91e42c1c06a526f6eb26e4ebf61c062ca50626a52cebf6e41cd4b4d3fbda76a53e76d43ea5d3fbb4dafb76dab43ea5d4d3a5fbd3d4dab4763e2f8191a3f31fb0b6394d999662c7877ec7397e8799964d6296c7624d7e873999887a0c3dfab4e3b2b488b2e30c3d7afa3db4fa7ab2e3880ce33d0c88fa7ab4b2590d9e5ac2c9b50bc9590bb59e5a0dc25ac9c20d0bb5599eb55a9e59c20dc90b995d45d6c547a6df4799dfa645d65dc5d647c55ddfa69945a6d64599c55d47df27e964dde295d886952786d864dde9e2dd95e2e986d827640e1823813dae0c59948e66129ae71e18e794181e66128e9a12e79a8e181e94661e1266949a8ee718cd04943889a727c465c00d2c0d65415f65655f410d2cc00d2c650dc05f41650d1d47dd97c2037647650fc9eccf70dd4c70654cddc9ec0fcfec70cf0f4cdd65c9e1a88d014f6724ec67e1ec248d01a84f01674fa8ec24e18dfb266485924af2343c423ed708f5d9f0f53cf0d93ed74208d7f50842f0d93c3ed9d73e3c0842f5f00dbfce72d888f44a880d4af4ce72bfd87288d8bf4af40dcef472ce0dd8bf884a50f147ab8fc6fcf5c650f5fc47abf18fabc68ff1f5fc5047fcab47508ff1c6f5cb38e1412ba04b26a0cb264be141382b41a02b38264bcbe14b41e1cb2b38a02600a4e0f7f5041a9da0e06aefe4ed3955eda055396aefe0e4efede4e05539a06ad21b7eba2a01449a39f9dbe455823d618239613ddbe4f955e48255f9613d39dbbc9db8584a5afaee5abceefab8589d4a9371723dc8fa1858fa935818723d71c8afb7c41bc55a40e85aafe840c41bb7c51b5ac5b7e840afc4401bc4afc5b75ae89ee1d377684d6c604d9e606cd377e1688e2c55d8bbd0036bd08e6b0355d82cbb0b81bda7a86e56866e0b8656bda781a8a76ea88186560bbd56a7bd0ba8816e8677e9df6979c00a368e88bbe08ee41228e48e2812bbe0888ee0e48e8828128ebb59ae1bbb071f74f11f59f1741bbbae07bb1f07aef174591b74bb1b5907ae1ff1b8f9cdae07f024055ea3be23d2da081868fcbd1ea3fbb3f7497e52011fbbeabe84398bad6e8625af629687c105852bd582cc245fdedae2becca70c478687d17cb1a3d6d2cdabf906dcad3cf0539375ea20b778694a4498fc0934d2d30a7dd1bd114fb84b863696f65d6a7ef9189d029210b7c38f85a880d315cc17193f7000a384bcb418dbc89b5e8ff0cdd0a5935750e8073ff71b9de48bfac4139a48d9eb89", "55c7efce855d32fa4e2721a890e3c4fafae48e4327a130c8a330e8eec45a27810f3174d3daf4626d05b3fa9d40bcfd8ccf853d5af24ee7d54e32da4fe7d585fd7c8cc2ec5e01402d78f6d604d12daae1723248d3b611e1f0ff5fb9aa979b389324aae176f618d1cd49ee0dd4ba89c265e0af8cd9da184173d89a790041f3afccd462722962717d11fabf713f4a7dd9e969f95afdbf316adf3d6aff7ad9e9bf517fd9a9f1ff3a4a7d88ae13b5a789b1ea72648c5941e4b2bd46f5a8081a75119150f1a6d4179c54f4a25414a203bb44d6e675764d92c38eb6bb03c2a244b65414a24456b4d4a2031bdcb7f4905454f106c6175c94b454f1f09454f446f1d017bc72d3edc46ce19d4353456476ef8de03b9b20f34d45646ff66d6f3693e05b45e496e05b442573ef6dc1ec44f29d63d36dcd6c81e3fd6453d2e49dc36d53d26ce1836d40585f61a59ab73072f5ad810b85858bb7a130f26d15e16d95970ba530b2950b25b290f7ad61415f9863a59a6d40239e4d8781f55eee9541e7e35e2e9e8d47f7e8e82c76d7c0a839e877da30d51b3b15c8b03968fad770fa1728d5bb39c837d53ba81968daf0f6ecc867d740f728e82cd660f748d7e768d7e048d7e72cf62c220e255b6125773fd6c8295e865efd9dfe5f26d628de4926dee99f5e3dd648895edd28f63f5ec6211b656c2537224e2e5b21770525622c6525372e622c5b011b46ca94df1234cf59b9242c58b6458dad855956b924384c36388cb9454db944ac45ad449939583692dfd41b340f46ca23e133293367a57e27336963a53ee133aac4c59587519bf7162acc0d4a114ce5c1191cca6f975dfc8a5d1cdcf9c16f17d6d9a2ddbf8ddb8691c7f54a9bb7c48585879157dbb5e4ca559bd7a5e48a87d1f32f9ff45b99e498c674b31dc25af3366d49f925498dd6731aa23d46f3d674d3c5c0484cc05d5b5e3d1e03626e3f9afb8c90f4f3e0e610110fd360c92336aed3f5fc192828ef584f892d39f1b667a0bf7fa0a9872df936b1e736b169a09f2db971a03f99ade9b6272f0848f558effc3939284fef18e85cf5e858eff95c35280f4540abb6d791c11fd0142216bd21fd34343db0c114023df6013d3630fdd414a236fd14c23410bd21b1b71685c15f40cbabd7d19fa156004596c15f4b00a5d7b14b3c9c9d35af6fb222adb6c1b60b104d11502281ce00a0a69cbd8436a02cef160110ad364dc2b6ab8f95bdab6f523c3cd79e39723e8a0d7c6a3e72970ddc9e39c61c092ac01c6ac2bc83877bba6391696971bca383679a9b639a7b7c91a983a77b9189a7637cba837102e70bc7941ef929c07c020acadc060a6a02c9dc26c01c1ee951070193db9439f2807f83b940e3a3e09939f260835f7983ffb94023f280bf40e320f27983991341879edb14e9111101d3945b0789fe87dbf411891e015380ac717e4bcce4c524213728e13a5a4f2f5ae43a213721483a2148245a2f21f7285a2f374124e13a6c6bdec0e485ac51714becc5649ecca0dee4a591cc604b6c6556aeab3cf9dfa853c4193cc15ec7535347d35ec43901dc3e015c53c753c4d95cc7d3594433c11eb9bcabe5df68562e811d91c78523921febdf486eb6a53cb97e9d9c85c3a0d4c47a7adf4e9bd6a794d4879a767a5fdbae56db8edaa7747a9fcea7747f9a5a9bd62b52e5ff305e0ab09cc3c0a49465dd9ea5d4847cdd9ec380d02fa729d352ecf891a187565f4f761c5c16518fa1479f764f9f1651769ca1475676bc8701515f8fd6f625307274fe0327d3f258acc9ef3049ec38c7ef30d3b24138396ba1d653abb3c8faa8b8ebdb34f43bb3abc8baf8c8abf828f3dbb4c8bae8dbd4ba28b3b8eb7621abc1534b38b979a156cb334bb821cb532b59b861a1365dbcf2c4109bac3bd24ce25cd311c3830383d2d14c42f3dc51f39c12c3c34cc21cc343c28c52d3f1dbf0249dac5bbc1221cb016324b0c79584acbb523cdd10fbe8ab0cb881a5a12ce119ae8ca93b99fdeea8e3a8fb5278c09ba9ec2199fd19ae2c991deef981a9bb84b899801227f1f4ac81a5ac01f82ba8b8a1acec2ba88105f5e92c9c9da43100c7e7ba1e41083e9b1b9e47c8e71aa13e08a19e073edbe75a1e3efbda870741a8843d1cb531e0e98c9e66df84ac505249bc31e0ec09959d24171bb14189de59eeea68d5f831be9e1fbf1e2afe68f5d198fed118aa9eff6835b89e7ff508ea31de5ea9e1d7590e1b9151895eceb901fb17c1590e11fb5789be670574d964293c089cbc1db42a47ed1da3138014fcbe9e40a70a145ced9dbc3d54edbd9d1cbc2a07c96419273c680574d46429287c790507393c087405c76469272c277f9bbc4ab0036b324eae07591fdf9db713174b494b53498bd75d1f17ab0e597f120b43ae2748537ac34f572580679b5cb02a3fac27bf4a3027ac679b3cb658eb151d8878e360cd91a50a7b177a0dcc337cfa0ead891cadc9138c6dfa2e6517da716da00a9b08fdf59678a3580b0b1d6883f8b5f856957843abf8161de810d56dc1d0aaf734d191dc114562171cc1e62efd3b2d0f5802c5117117dc915c71179cdc111145c2ca7021b0f714d5cdcdd0eab4770135d0a1f7d40d35d0d06af5e0232b9e6e63d7f61e8dbfd763747fa40037bfd9f5009e01c36bd477445a1bdd37c94f2ae063572e3ecb7563f7e083239e6e7723ebc0f56b63f7e3c0359e2ea55accf230b8a070931fe4162f4d8908df2076d45aba79354e9dbb95077e6ab2ba3781467a5aa12fe4953067b1d5cdb09a8ff994e1c8f030dc579099e4cb5b5b40b24bcd2f1fa3537c11fde0e77ea393d38b909716631b790aea11be19ba74f23d519f784213297bd23ee20977c9d0c660b482f922e3070e701ae276f8b11015", "58dfe9240415729cbcfab9b0474bdee9aced21866e5a9b5e9fb16056bf1388b7b0df4946fbe9bcba46bfeaf8ddb9b04b24701406dd9d58eb06599fdc71e82414351ccfde9a20ba45680efc95315b1b23ba994435dcce1e23b82cc9bd815a375195195b330f2068fea8858f5198dd2b0067f2ff2b57f572131c5e4e0669da36223b5dff37ee47a92fb6578e8c312b885ca9ef2f3b35fe5f47561dd175a2f6343122d2a81e1541a32e2f825a4c2e452cae37aa47ed5f2f3bfded3b2d5fabff3746c85a948a427460971edef8828b92962a604394c88a965a74de80fb961e928a2a8297928ade281efa8a1e2ade94fa82938a6277405894c896d1d6bcceae4972d87c67aa88cceebd114aba992d70bc9f6cbdcd127c8ba864eeba2d989d48be736c2d9cbc73b86d4a9a73486eba9d982dbc88bcedcd66127cabcd7e1364bea988eca1f01646aebe3570cb7dc4b3e930b0de35ac72a14416f2be0d28e80b73ac54b3b3b132e87cdccbc55473b00d08eb2bac4636bcadf272a114ada270f1361446be7a033507fd4e1ba6fa1c9dc51aec1ee91bfea67a0735034d1ec59e1df9ec1ae8c51eed1a1ce9fa9c1af8e81e1d9dc5ee07194eff02a57a37ff7aa7021936074dabffc71a39c5cbd08cc5652be4aea044cb38d1ab1bc5fec7c42964a38cade4462ba0ace4c6458c65e48e45c4a1642bac1ac9c43bfdd3abc73ba9d3ffcbc41ac5a8312b978405cbb6d46f247c2665e6accb86b5a8952833074859f29b7a83e6c17ce664266dacd427e679c34899f25b8297c8068731b7a82987a9b530cb2a9704a9dc4285b94129825cb9f030f26abb96dbd03a5bb4fbb771b830f2b85e69f39630ba6af3ba945cf1f35e95b8b8f2306aed42b18b833b3ff88b3f388343f9edb2dec6986eb643586b228211927e1edc1ccbab18188909b86b73bfc76340cced4775fa611a2c79c4c61c73fee5937e2b936e5a43b4c768de9a7aae2d29bf24a9d1f437b12527def60cab3e07e5e91d039df6240ef427b335dd3fe70501a91eeb9de5011deb3d9fab06eba99e3f0305e51d25f7dc26360df4b326f60f34f5b025df9f069a42c4a237a4a068f53afa33d40a37c4a69f429806a26839f6d6a230f80b3ad632f86b09a0f4f8a30868d5f63a324234a0c706a69f9ac79ea607369842a0a249a4d536d8760181efda3347ce47b1763500a2d5a649d887e7b1b277f54d8a3347cd47eeb281db4d768987b3b3e6f5dd82b397d00694e5d434024a24d01900328d77f0704f772cdb2005984f40419977702f32f1748c4f233f4ee07ce198d29843414d2099db044dd8982341059843f0744c738f2f327573332d8e7774f04c683c471ef06f3017d13f22609a72eb2030f317681c443e6f3d6222e8d0739b2260ea709b3e22d1239bd2233dea2060721e306ff03f176844f06b143c33471e6ceb8924e406255c4719346e89bd98cc935c0745ebe5268824358a6dcd1b98bc9089cd9bbc3492196cbc189035ce6f8999e45e27048944eb2504e9458b5c27e426786a8a388327d8ebf223b023f2b87044d883eb783a8b6826ca259777b5fc1bcd2777fd1bc9cdb6941bb5ccca759527ff38db27806bea788a807bea68da8b382794524fefdb69d3fadb9373189894b2acd3daf994ee4f536b017645aafc1fc64b18b0949a90afdb739ad8af93b3701894efd36adb51fb944edb95fa50d34eef6b8e2332f4d0eaebc91de6645a1e8b35f9ebd1ca8ef73020ea7fc0dabe04468ece5a36891de7f81d661d1ffae534655a8af4e8e9d322ca8e33d38ecb22ea31f4e89b6616591f15777d37242fd46a796609771d7d9b5a17651627d72e6435786a09d466796a250b372c6a350827672dd47a5977151f657e9b161f997e677615591778509a499c6b3a62b8326439608c04f63a9e63784898516a57621b9ea493758b629f9075578aa71b75a78b579e18629349386a9e536278989e7b60503a9a4968b33f3cc395317527059535b09435007f759725b3c33d3f309e9e10371350e224b0003794957d053594057d950137b034c37533953d24b33f0fd81d751c755f0a67f3f85cd72308c12ac9d3ec9b90154a08d5c3675ffbf0209d91b087a336063c938437069c3da1b206a03e9d85b393345c0b21d4f3c067fbd467c3f308f95c23f3431dad1a3fc6d7ff222ad1cb393760c61bd7f3af1e413d23d22b35fc3acb61d13738cb2162ff2acbfd62233628d13badc63f1a43d5f31f1af3d743c51fad3ebd8393b78356e5a8e0809a2c05852fafe580aabdb7938357802e992ce38407ad2c2d870781aee09807e1ac802e9b2c85b7e7548182abbd93136874029082dfd7eb63604dc6c9f520f5e46c930b56e587f5c421eb4f6261c80410694a6ff8e9aa93e75709e684f56c09f684e5e46f935762752a69f1baebe369e9bbf376e26229420fac39b25461efdf6aa1036d10bf1661b3ec423bae0d546b01a1bfde126f1403bd126f6815dfa26fdc166bbda20311df85a3357982b14d35b18179864fdfa182233a923ba248ec06ba195a9df62ea04838ee82933b22a2ba59192e04f69ea25a2df49ebaa1061a9e06a2ba2d185af5924ba03822ee823b012bd8dca57fa7e5eecfdea3f1f77a8cb87ec4d3ed6e641decaafb26f949057c7cd0c567b96eec1ed3656dec7e1cb8c6ecba1e7c64c5d36d6b2360788dfa8e48c09314e0e637bb1e1161f283dce2a5291e46f3319f321c19f445f726d0484f2b1996bc12e62cb6ba6b8bfb0a32937c7914ae548b591e06174dd6a973b7f2c04fafe61bc48e5a4b3774922fa21ffcdc6fc0018c56305f64fc65af27ea134f6822da58da473ce12e19a2024e43dc0e3f16740a4876a9f9e5634e5e413dc2374397236f7a11f2d2626c", "3b9d573f17f668c96b9d048ec2a0bb135717f63bc9683f9d76c9e8571dbf3b1784c220eb933b0e9d8e13eb3b9d84a042f1f63316ccea7702d38bb53dc4d04d6b6304cd81bf32666b6ee24cfe7fe5aa5ecdbf32636be601040500b5f0310ab37b4684c3cbc9204ddbb7a886e3d95b1344260a9725b93750eb63443793a886dbd991cbf6ca91316605a7ff46f5a8fdeb65d445441ad5a32268c5f545508bc9a588c6a87da7e56bf5fff565a7ebffc6fd2826c6aa23ba4ed49eeb28f5fd65a7c6ff52c5c31b5f7051d2d95251ec0e088b12435ff05252d11bc57052d143c59b525f0e3bda9ad7d93549ec12598b5251880e51c51b70dfd243528b0e6c881259d152934d4937b3058ef76f1591b7bdd94c8249b38593770eb74d85770ec94db713b391bdd96f82cc37153782ef4c1591d9bd8e4db705b313c977ccbdb759826f1195d67bb98f78361d0694c2c886b7555e2eb9783656069d8f7b85956a0eb601617dc8b755142ede86c2062e14dec2c8d5b76ab601057d618e95deb786552e94c842235d9fa3b35883ddefe620c3e95fa0549fb3d8a35d83235dd85d031fdda3a3b3a0e95fef5420c3e6c3546fa0e6a0df6903dda3d8b3239f5da069c3df54efa0669488b1b86c85dc15f558239978a77f7ab16c059495dcb8888595dcb18838946ca3782775fa7f9958197af5ff5823a778dc8838856c94b195ff7819277a75a3d89c95fa8d84cfa4cc35e512d9e030e616fa84cf9ccca48d954bd03c6f1829537e92e030b5166659e5d9163566e592b0603c18294b7e536fd0e660d9b016b51265d7922b171e465e6d07bf5d28767170e72b1e46576d5e9792466ddeab1217571e5d76f107677028bf4530955ba8303728de1217461ed72b6d366e1b5a678b76ff9b43443042d2cf835bd34d6b88f618cdd8b84e3f4c83258f659263cebf7cd26f355acfb525e597246bcddb18d3cd7608fd68eef7780c88b9776d791503233101a073d5e7a03cbd637eb6e49edbc4a681d5a03ca063bde773bc633dd5f367a0a0e4dbc4fe81a61eb69e81fe26b6e4c4dbbdf3e7bc2020d563a6db9ec481fe64b65a0114ad5e477f8653538806f4d8c0f4945ec75a067f2d0147067f1401adda5e08f4d8d3f4c0065386f4d340538858f47f012dc7de5a140640f486d8f45308d32836f05d7be6c8f9b2bc5b70f612da80707be6a8f9c85d36bcbec92ef17076d603809a464089043a2e403489b4da06db49f1f03c56f6aebe09dbae0640b4da3428731ba400f30928a60e9e8e69eef1459b007328a809247373a8091b7324a8009e696ea6c5f18e0e8e45a6f10e1eeee9537ae4c7099c2f1cf1e90eee45269e8e1d24fa47044c536e8dc803e60dfee7027a044c1d6ed347244c6e537aa4471d04830d7e8d8267e6c8e6028de7c803fe0d53a4474c041d7a6ee70d66fe028d83c8793283c62db11793bd84dceb84209168832db1799397463231931703b2c6f92ddc8420bd6891eb84eb683d9184dca08417b246b1ad7903939184eba068bddc048e487e0476441e174f1167fb04704d1d96f2e4ae7f23b9d9e47fa39659b9aef2e704704f1d4d7b117b1d4f4d1167f004a359b9e4f2ae967fcd047b701d4f671196757b720e039352d2e97d5a6d3b6a9f7b0e03965213f275835213fb7572160e7d6dbb521f6adae95a9f52eae97d3b6d7829c0ae4895ffc36a6d5a3b9fd2fd6926bfc39c4ccb63b171861e3d7d5a44d9c34ccb26b1e31cbf4bb1e343bf9ca64c1e7dda7159443d863dd97144861e5a7dd1f90f58db97c0c8447d3d5ad9f11e062ce186e4855a2dcfd322ebaee2a3cc6f8685da2c4fad64e15a4fad06e1e4ac85ebe223d3efccae22ae6fd3cc22eba3e22de1e4da85ac064fcce2aea36f53eba2c01e57862c078c910f330947cd734a0c7443ec13b2ee4af16cb2ee74f1ca134309cd730f0c4a4733470c0f4a3389734d6ef14a6cc39374b24a4dc7730c0f0933e0afa0b20696b206f667b86ea6b28764a00616e086b2b2af9686b2a0af32e0064be101bba38ea3eeee64f68767b832a69cc4d313e266024a07a6eeb26476b8e7424925799a7d13b26c9f6b21847a1ef8547692f0c680b32792c600d4a7b370766b84fa6c781e219f21f86c1e9feb7a0480a73312f670d4c61e04a17af8ec6b1f06ec5f44257a39e7fea3d5f84763a87a5f25fa06673944ec7a67b95f6cc40625d54763fe7aa8f8a3f87a7ea8a355e3c7396c447aa5865f67a8c778e37afed523e5151c5093a5a0f077f2f69c2a5070b51c93a5e5f020d015a5f0209c15d06593fb7a028d4e0052f01cb57770f276d0aaa015d02593659cf0f0aa1c50b5f77672fcb09e9c6d72c1aa7d5cac4e252d5e779e6df2fc2ac19cb0f22ac19eb09cfc6d2c252d7d77de4e5c1e647d0cacc938b95d9500224de90d3f0cb99e3864fd492cd7e25b2d74a00de2b6e9bb70b4264f305b74a057e20dade220e28ddb62ad57743bb4263630cff0e9ec5de8813547962a8d622d20f4d75be2812a6c965d68c7b505d4403743abd3de704772091447c45d4043ab85de5337d4abded34054b70543b43c60059bbbf4ef895d7044477247145354372bc385c0de441409c75d707247ac03d78f78badd8d11696d040caf51dfd778baac8ddd8f03ba8d5dd7838fac78d703789202dcfc668fd1fdd97b34fe5edd830fbaf82cd78d808f5d75df243fa923c3c3683ee65386f8a9c93a75ee561e2f6f6d715f416692e082c2956a31cbc3e9e6d57c83d8516b3425224c7e905bbc5637c39257c29cc56985bee8de041ae98c1f3880d10ae68be8d2c92ba847f866c74254c06988dbe17c8c4e01c92e35bf8c6de44d2f425e5afb8d4ef245f4839f25431b4bfb8827dc4da4ecf5447de209", "7762ad93c05118744e20de7ec68259fda1935018647d72c754c871627da79310696d7ab1b68718ba2d79a7f3eae7c21ee7c22e19fdaae377a7f3eac27e2719edd5cb4d9cc9ffaf5c6add44e1b224f70669db8870783919a482e816d5703c7b6b3b7b8ce86612d5706c6d8ca039f057c676af00a0163e466180a0f957666ccd3cbdecf4dfa81eb57fdad3c4587544d789fedf18b5efb47cad1fa5beec74fddfb8f87f1da5bebfecd4ac2072d95e3932c614b1b8be086a31b9048dba8848a37a5451225b2a8add0161482aaa7803ee5b7a26c961475bf33abbd1815d226b512a0a5a6ad1810d51222b4a5aaa7878e30b2eea0b4e2a7aa87853a378e80b5e4a2a7a49f0ad22f2b6379bf9ceb1e9b6607622a622b237fb4d90f9bbf746f09da92232a292b9f7364bf02df17eb229e966b6c062b6f0ce21b9e976b62969b670f2cee1cb855218d9f0b6cab152cd36a0a02fcc5018f9b68ac2c5dbfad6c085c25b18b959c8fbd6b0ca8512c3c07a2ff711cfa6acafb052cdc13620712f17cfc6caa0f394eadd1c6438fd0bb36ba07b147b76e4d81c34fdeb9d0a643b6d98ea0dd41cf4d40c346df89bea1db07ba4eb7374166b7416bb6be0a37b74a4eb73167bb46b704faf1e6b2413eff4b6921b11a7908d32136b14efa44eff2f142f43affe1f6be414fb1f2fe344af6ebb8212311697ad9092adb0923b161187173196ad80b2921bdca2a65c221b1cc60d9a072365c96feaab5c121ca6d6c22c162cdba2c6ac5c12a2cc1c2c1bd6a2569499b352bf91f099ca6f099ae70d2365b1529ff0999399b4eefce0b70bc52e0ea5cd5be2c2c8e37ae5b7cb2efee00c0e06a508a6720b15e6eedfc66d43eb6cd1abed5a72e5c2c3c8cac3a8cd7b55e2e25272c5c3e8aacdeba3796bba690dd11e31b71fcdfd1e8f0192a446ebb9b6a4fc0e61ad791b63bad926e0ae2daf62602479707388084648fafaad4c72ccf9974fe4111bd7e98769b034d0cf96dc739bd87aac77fe9c1704a4c3967c9bd83fd0d478db33d0dfc4969cccd674db9338d09f770c74aefa1c94a7149477aca77afe0c7cae1a940774acf7987e6a0ad1801e1bc2e02fa0e5d85b8b600a811e7b9a1ed88bde907e1a680a11611a88de109b7e0acf502b80a2d5ebe8dbebc8e08f22a0552580d2eb58cbe0af1b5096770bce5e42d537291e9ec7cade40670050d308289160db0588269156db9b2661dbd5008856391fc506be6bcf1cce9ad737d9251ececb066ecf1c351fb9bec8d4c1d331cd3d85634a8ffc3881f3d1c133cdcdb438de3dddb1c834dec1c3d3313eddc1bdc8c40105656e8314603e15600e3561638e04646e13600e0535815ca01179c0bcc1ffcf6d8af48889a0431c79b0c1af51f0ccbfc15ca0f11c79c010f9bcc1cc5fa071caad8344ff8880698380c96d4a8ff4a888448f80a9c36dfa12ad97907b9d102460f242d628b6356f9d909b10a4172d7294701dad2792901b9b2092701d14ad9762324f66d0b825f6bf2566f26240d6384866b025366ff2d2a9e329e26c9f00aef26f342b975cded52fe29c00eea9a3699e60afe3a929e20c2ca299600faee3e9e3c211c98fc08ec8559efc6fd4322bd737db529edcf56f24ed533abd4fab6d477f182f05d815a9f23bbdaf6d57ea434da74deb534a3dbd6f3f4dad4d6be753ba52cab26e4fce6160c261506a62bf4ecebe6ecf61c0526a42283bced0a3a74f8b18393aff016bfb12c7d0a34f3b2e8ba8abaf273b8ec8d043c380a8af472b3bde2cd6e47798936979946929767ce897d3e3779869d924769cf96d5a64dd557c94e0a9259c5cbb90d555645d7c64fa9dd954dcf56d9a59647d5d9459dc75f46d6ae59925dc90bc50abb550eba9d5209c9c2cdcb0509be5a99589e16126e1a8794e4ed62d5e896d78926826a179ee8141e9aee988e1416926716146a9e9788ee1213112d8e3ca90e58062884dd69d2e5e79299e6e887d42d65d90ccfe0cd7cd54f6408993787a42dc4cd47d293c6077d471c6d49dccfef00c57f7fcc0d45d96cc0ed600fc1554d6c052dcc0d25016f45506f615d4c002dc5056039fed732d8450cfda18f07446c21e8ee4738d509f0dcf238f20049fcde3735dedc38320540f9f7d425628a9244fb36fce4ed21880fa7416f684ca4e12de187055cf7fb41aff680ceb2c878d48afd4f07fb4fa68cc5f0f15fc185fcf0f75b46a7a04f5186f5ccfbfe7dc80fd8ba8442fa044ef2cf78b8dd888fdab44dfe02c87aef64ede9e53050a131eb402ba64b28c0a7e5f4fa0d109405a95a3f60e4ede0e4e0e5e9503aaf6de14bebc82036ab2146cb2141e84b302baba8263b2b41c1e04ebae8f8bd5a9a4c5e1a7ab1240a429bd898ba5a4a5efcedb27d783ac8f813519898521d71387ac3f58951fd693b34d2ebf4d5e25d813969313d6b34d9e5f259809c6367d178ed6e44bbc51ac0584fe7a3e7d87d6c406e6195285bd0b3db0e6c8b8365085cdb20bed41fc5a7cab850eb48a0e44bc715bacf5557c8b0ef44abca1b80bee482e81e288d87b8aea6665b810fe9d9607ac6073978822b10b8ee848eeee888822e1b80b4edabb801ae86668756068d57b1a88eab6861a6868b5d07beaea3b22ad8d80e135bab17bf041179fe5dfec7a004f52809bdfeb31ba3f7b8fc62715f0b1abee9be4bb9175e0fa114fb7154fb7b1eb7af09171e01a4f97b5b1fbca033f3559a7ceddb3d8ea6658f24a986a2dddbc9a6f103b8b97a64484c90f72233dadd017dd9b40ca70647818cdc77c79185c50b8522d664cf2e5ad2dee2bc8df0c5d3a7905f50884bb646863691ff14b8bb18dbce945c8f073bfd149be887e3ca18994bd9ea84f7c91f10307305ac1e6978fd12920d9a53bfc58880a380d71", "abdf09c4dbcf5830fcee5cd825a35f754337ad4d2fd6f610d8a325ef745efd5ca3fd745e5dd8ef2483ee4eac7512380a12820a394eacef74ee3874120a83ac4fde40ad9b285c96e428ccee1500d4c2c71a6e678f11dd4ca2ca98ad8d113407fe99071034ffca8cad95ab7ab98933f9ff6f4d10dda21a8e6783346d1b110e2f273a517b9a18ab8ee826972216d717412d9d1affafa3d4f797c69815442edb2b478f8aa05117116954f6af979dfe1bd5a31bf7a3d4979daeffafd5ff1ba3f69d964b0f4945156fc07d6f4a7dc149450f1564454b2d3ab0214ac145494b150f6f7c456f140f7dc14b49202c4a644b45b13b45213ab04b642d4a67d72439ec686b5e4e24df3936dd16ccdd4ecc16de392437be455432f7de66091638de4f3625ddcc39dc3625cd164ede663309be5544def64466f7de08be335532df5444f666bf09853956aad90614f40684f51556aa39d850220b79df1a56b9d9741858efe53ee2743eeee5e2d958195679b9500a231bde2357df1ab850780b781b0a23df5651b88e7c760d748f62cf8f8ece62770d7c74bd839a81a60d7f53620d768f747d8ece0d8e747dce628f767f8152bd9b830ca7837ea70d53bd819a810c9b83a67fbd5351c6567223e214b2e250b2155672c722d58d62ffe3659ce81572575022c6e2b272e322c6b21550569dfee9d5638d64e28d9ce265e8d5ff63ff65628de29dd4e94dbd41f360a42cf9a44cf92d41f3bc61d44a94998365c35a3e93327356ea3712933656ea133e7332c3985bd4944b64834bc282655bd498959865954b82c3d45a5cafb4794b5c18795c5c7918b579af4a2ddafddbb86d689d1879b55d4bae5c78795d4aae78185db5c5c19d1ffc76a1d8c2dca014c1546ea1c1a1fc76d9c51f9c3120e6f6a3b9dfe3f249bf95498e39ff8cc404dcb5e5550c493f0f6e0e11c1080d963c62e33afd30da63346f4d37ad2137db21ac356f634c945f92d4683dd79680548ff5ce9ff3829f8182f28ef554cffa93d99a6e7b1207f2f48e81ce559f83f59ecf5583f2808e139b06fad9927b6e92136f7b06fa9bd89a7ad8926f13fb076b5118fc05b41c7bb46a7b1d19fc51044f214c03d11b62d31dfd196a0550b47afcb504507a1d6b196303d34f4d211ad02162d11bd24f034d031b4c21d0634fd3d9bbfa26c5c3f358c3d959f3fa26bbc4d16ad3246cbb1a009923e7a3d8c077ed2377d9c0ed99a3e64b6803caf26ec1d96a1b6cbb00d124d22512e80c006a1a0170be704ce9911f2791a002cca1266ccc99783ac6a73bb817cc27a0a0cc6d90022690cc6d02cca1a0b9c717993a783aa678b8a73b1699c63bc73b3a78a6b9991674e8b94d911e31111e751030b94de991340e229f3798f90b304db97590e81f114d1f91e8113075b8f89f0b34220f98370ff837980b349e239e99230f36f8350ae60d4c5ec81ac5b61ae7b7c44c5e0cc8f572134412ae83a2c45e4ce6c90c1ab75e1ac90cb6c4e64d8244a2f51272af13728312aea3f5441245ae13721382f4a2bb5afe8d66e592cbe5baca93ff8d5a663c9d453413ecc17511795c3822f911d88de4665bca93bbfec035753c459ced139cc113ec753c354534ed459c13c03d7555fe0fe3a500bb22c959380c4a4decd74af7a7a9b569ed7c0c4c4a59d6edc9394dc8d7ed390c584aeda87d4aa7f769b5f7edb4697d4aa9a7a869a7f7b5ed4a7d5f022347e73f606d729a322dc58e0ffdc77b1810f5f568652d8fc59afc0e73328e73fc0e332d9bc4691165c7197af4f47a68f5f564c7111911f5187af469c765b21a3cb584936b1793b3166a3db51a844dad8b328bbb8ebe6ab53cb3841b9217b592851b166ab33c8f32bf4d8bacbb8aac8f8abbbe4d338b33bb8aac8b8f4cbf4fd2c9bac52bb10d2b4f0cb1c9bad3c53c24cc28351dcf311c3046027b5c19b2ba2bc5d30db14fc8cf29313ccc241c3524ce351d313c28cd281dcd2434cf3d309b092871124f4f88ca801b581aca82bed9e19e1f98bacb9258ca1a80bf82ca1acacabe821a58801bca1e92d99fe1ba99e1ca98ba93d91f9e3a8eba2f8507ec8ec3511b039ece48d8cec2d9491a03509fb3af7d781084eae1f64dc80a2595e46903ce9e50d949c21bea79e0b37dae8510aeeb1184e0b3797c79847cae11eab3e11a7e9de5b011e995111b94e89de57eb1f9578fa01ee38debe8e59c1bb07f1195e510b17f95e81b9c8da1eaf98f56e31f568d1fe3ebf9a18ea1e28f561f8df9eb9671c2835640974c40974d96c2837056dedbc9c1ab7240d59682c2975770404d834057704c9696c340c1d5dec9db73aadb41ab72d4dec1c90148c1efeb09343aa537fc745502883472f2b7c9ab047bc2f527b130e47ae290c905abf2c37a72b60473c27ab6c9f3abb478ddf571b13a9526e3e47a90f531b0793b71b194b4f4dd5f6f89378ab580d0b55ed18188376e8ba11dd706aab059768136885f8b6fb5d037b48a6fd1815e899a3cc1d8a6efc2d11c59aab077a107d63cc3a7efd09ad8c017027b4f51ddac0cdd160cad7a4f0351c1c91d1151241c77ad4e7b175003dd0c4fdd50030dad167a1c1177c11dc92550c91d512476c1111deed2bfd3f280156cb35c37760f3ee8e23eb2e2e936765d0f93fca4023e76d57de97637b20e5c3fe2763f0e5ce3e9b236bc467d47a4b51130d1f87b3d46f767ef70f39b5d0fe0490a0973165bdd0c4b5ec52c0f830b0a57aa1368a4a715faa27b984f198e0c0fa3f9059949bebcb5c57db95b79e0a726ebd4416ef1d2948830f96247ada59b57f30d239e70970c6d2cedbbd4fcf2313a0524f589273491b2d7132b982f327ee00046216e871f0b5101a71ee19ba14b27afa0d10f7eee373ac91708796931b69137bd", "ab8edf9d0bbb64f49d4e425021c789f59d64b49fceab0bfb4761d0dd89b54e02f5c91d874e4261900b66f53b8178fb199f0b7bb4e49dceab1e62e8a6b5e9c5daf81885d9bd02805af1ecad09a25b54c3b135f30082e65f99ffbf72552f377126e56490a66d23c2e192dc1ba8751385cbc05f19b3b53182e64954c3edec31a29ba8c5e452c4e2fa22f57fe37e94fab2d38dea511134ea22227ad4fef5b2d37fa3d3f2b5fa7f63d4be115d276a4f1363d5e5c818b382c8657bfeb253e3ff7594faa1e24da92f38a9e845a92844077689ac29a9e88de2a12f7876078445896ca928cdebec9a24871d6db86fe921a9a8e20d8d2fb82869a9e2e14489ac68a9450736e4a6db89d9c23b87a68ac8ecde1bc177c93b87dba6a4d9c2dbde6c26c1b78ac83741e69b8ac8deec82d989e43bc7a6db9bd902c7fbc9a6a42cc1b7884ae6dedb07db80b0bec24a356f61e4ea5b03170a2b83cec7bd5c3c1bc3db2a2f174a61640a176f4361e4db2a82be30c74a35db80473c9b0e03ebbddc2a174a6421ef5bc38feed1d159ecae815073d0efb461aa37d1aec191aecf59ece1f42f50aa777390772a906173d0f4afecd991cfae81ee51d159acc1ee91aecf6faa775033d0b4e158441c4ab6c24aee7fac9153bc0cbdfaca4a6e5cc458b6024cbcd33fbd7aac913afdbf4cac51bc934236cad84a6e449c5cb642ee0a4ac45813bdba51ec7fbc8c378c9429bf25689eb3724958b06c8b1a4e66d2c64a7dc2676c7018738b9a72895a0bb3ac7249709825bfa937681e8c9446c2675266ce4afd588b5a893273b06c55898b2b0fa336ef2d54981b942298caab36af4bc9150fa314bb38b8f383df2e83333894df2ebbf8238feb95366f890b0b0f23afb66bc995adb345bb7f1bb70de75f3ee9b732c9318ce9663b84b5e66d1fa6c192476c5ca735447b8ce6ade9a6da92f24b921aade77b3c06c4dc7e34f71821e9e7c1cd21228a81919880bbb6bceaf9335050deb19e135b72e26dcf407fd0b1def3b96a501ecf6d62d3403f5b72ff40530f5bf26d625e1090eab1def97373509ede31d0b9eae2407f325bd36d4f8a80566daf23833fa029442c7a43fa692d83bf96004aaf63037a6c60faa92944697a608329047aec636f2d0a83bf809656afa33f43ad008a6cfa298469207a439778383b6b5edf64445a6d836d17209ad47ce42e1bb83d73387b096d4059de2d23a044029d01404d1e2b7b57dfa47878ae3d73e47c141bf803205a6d9a846d578d3912548039d48478070ff774c722d314d40492b94d8039c734f7f82253074fd3e2784707cf3437e304ce178e293df25280f9041494b90df722134fc7f874073dd2a30e0226b72973e401ff067381c60eb7e923123d02a6f306ff738146e40146c13373e4c106bf26820e3db729d2232302a629b70e12fd7f81c641e4f306330159e3fc9698c98b48426e50c275b49ebcc94b2399c196d875429048b45e42ee5eb4c875426e4290d8d6bc81c90b59a3e396d88bc93c994150b45e6e8248c275cbac5c5779f2bf51a688337882bd8ea7d7bf91dc6c4b79727d02b8a68ea788b3a78ea6bd887302b8727957cbbfd1ac5c023b228f0b47243fb88ea7b38866823dfd3a390b8741a989f5f4be9d36ad4f294ba909f9ba3d8701adb61db54fe9f43ea90f35edf4beb65d57a4caff61bc14603987814929cbba3d9d4fe9fe34b536ada15f4e53a6a5d8f122430fadbe9eec3893d8718edf61a6659e3e2da2ec38438fb82ca21e438f3eedaced4b60e4e8fc074ea6e5b15893df61adec780f03a2be1e837072d642ada7566691f55171d7b76996a756b270c3426d57f151e6b7699175e97766579175f191ed425683a7967072f242ad9667967043d1b7a975516671d7ba78e58921365977a599c4b9a6238607095977a578ba21f6a3e63925868799840706a5a39984e6b9b6e1493a59b77825439603c648608f2b3986878419a5a6e3d0571970034b4359c3335c19537732fb704359d95750030b3753d94332fb335cdd51c751f7a5f08009713301254ee2e959034b5903f0575059323bdcf3035377ead359383b4963008fcf753d82107c367863c0d9132a3b4910423d0f7cb6cfb5363c8f90cf35427d097b386a63c0d3193ccdbe0959a1a4923d7cf6b50f0f82502f36628312bdb3dcd4d1aaf1637c3d3f83b31c22f6af127dfca331543dffd16a7f3d54fcd1eaa331bd52c3afb31c3622a212bd9c7303f62f713dffea11d463bcce0ae8b2c952781038793b68558eda3b727810e80a8ec9d24e1528b8da3b797b46270029f87d3d8192c9324e78d00ae8a8c95250f8f20a0ea8da7b3b3978550e4f584efe3679956006d6649c5c0fb23e7e95604e58cf3679a79216afbb3e2e56be3b6f272e96929691a6f4869fae4a00ce36b960557e584f1cb2fe2416865c4f6db1d62b3a10f1c6c09a234b15f62ef42bf18656f12d3ad0385a932718dbf45d1b9867f8f41d5a1310faeb2df146b116163ad006f16bf1adcb2eb4e3da40153620aadb82a155ef69a223b9238ac42e3842efa91b6aa0a1d5048a23e22eb823b982cd5dfa775a1eb095e14260ef29aa9b9ba1d569ef026aa0e32e38b923228a84ebc147563cddc6aeec3d1a7fafc7e8fed6c6eec7816b3c5d0286d7a8ef88b43649016e7eb3eb013c5d7c96ebc6eec107473cddee46d681ebba6f929f54c0c7ae4ab598e5617041e1263fc82d5e9a1211b8af2033c997b7b69d3a772b0ffcd464be41eca8b574f36ac92b61ce62ab9b61341ff329c391e161746f028df4b4425f8064979a5f3e46a7f922fac1cffd4627e034c4edf063212a15d4237c3374e9e4a617212f2dc636f2a57dc413ee92a18dc06805f345c60f1c7aa23ef1842652f6", "b1bed349082ae43879f573618f96bcd30cb23eb9e3d049283f63c1ac7e27106f58db430cddb436bd8c7ed5f1bb73619749e0280cba3bb1d661bf938cf6d379756a389ebd3541748bd01cf82b63b6364638bc9c0cd2b46d447059927b03b56ea27433896ab89d3d46500b1fa330bb5700cee4ff57aeeae5262b33b6661e40d0fc76bafe6fdc8f525f6caf1c19635610b9da775abe56ff6f8cac3aa2eb44ed696252df5f766afcbf8e5f04b5985c8a585c6f548fdabf5e76fa44a4513d2a82465d91b5281585e8c02e3cbcf10517252d55a3ad799d5d93e4b0bc01f72d3d241555c0862891152db5e8153d54bc29f5052715c5ee80b028912d052f2515bd513cf4f8ce541199dd7b239474335be0783fd99bfd26c87c5311d9745b303b917ce7d87b9b25f81651c9dce790dc743b315b781179db9bcd24f8565b3879e770db943442e12d8c5c7d6be097fb8867d36160bd5b45e1e26d288c7c1b50d017e658a9666b58e542892ce47da9e6601b10d657588c6c785be5e54229676365d0f9b8978bf5066a0efa9d364cf5393a8b35d83dd2fef54e05326c0e9a3d8a3d3bf2d935d036fc4df50e6a069a35f0d13d3a3a8bdd0e329cfe054af56e8b3dda3538d2f53957ff8f35728a97a1188bcb56c85d41897752a7ff9789358a8853c846195bc98d9771a257378afd8fc91d8b8843c9565835928977faa7578f564059c98d8b18cb5163562e090b966da9df48f84ccacc590e536b6196552e0991b2e437f506cd83960d6b512b51660ecdf3869132e5b7042e910d0e636e5153f8ccc94cda58a94f53b9850a73835204b972e161e4d5762d177f700687f2db657161e471bdd2e62db6a175b668f76fe3e6bd2a7171e561d4db85621707777ef06174d5e67529b9e2bc8d31dd6c87b0d644042324fd3cb839f55c5b527e4952a3e67e8fc78098db8f96573130121370d739e6fccb27fd5626ddb486688fd1bc35ebf4c33458f2888de86f624b4ebced19577d0ecad33b063a4dec1f68ea614bbe7fce0b02523dd63bed491ce84f666bbad6533d7f060aca3b4beeb94d6c1ae867ca033ad67b3e570d3f0d348588456f4840d1ea75f467a8158f3d4d0f6c308540d072ecad4561f0176f884d3f85300d44f04711d0aaed75648568408f0d4c3f3575ac65f0d71240e9449348ab6db0ed0203dfb5678e9c8f62a869049448a033000fcf6365efea9b14ed6a0044ab4d93b09bec120f6767cdebbb05672fa10d28cb678e9a8fdc6503b7641aefe0e19eee58b7410a309f808232e6665a1cefe8e099477e9cc0f9c231a5eee05e64e2e9189f9ab03147820a3087e0e998e61e5f64ea3087829a4032b709d0788e3ce0df602ea27f44c034e5d641e0d72878668e3cd87ac444d0a1e7364560e62fd038887cde36a5477ad441c0e43c60dee07f2ed088c0d4e1367d44a247d61349c80d4ab88e3368dc127b31992708d28b16b94ec84d6b14db9a37307921b80e8ad6cb4d10497931206b9cdf1233c8bd4e081289d64b129b3779692433d8f1d41471064fb0d7e4476047e471e18800f7d4d1b417714e954b2eef6af9379ab007d7f17416d14c376a9995eb2a4ffe71b64f00d7d4f1144feefa37929b6d2929a59edeb7d3a6f5b727e73030296559b62bf5a1a69dded702ec8a54f93f8c97a6b5f329dd9fa6d635b15f2767e13028dea7d5b6a3f6299d30602935215fb7e71d4764e8a1d5d7933bccc9b43c166bf2a71d9745d463e8d1ff80b57d098c1c9dd7a3951def6140d43b3ef4cb69cab414e8d1d3a745941d67b46c123bcef13bcc36cd2cb23e2aeefa6e485ea8d5f2cc123e32fdceec2ab22e4eae5dc86af0d412ee3afa36b52eca2cd46a104ece5aa8f5b2ee2a3ecafc362da8cdf2d44a166e58f0a0349338d774c47165c872c01809ec3cf7c0a0743493d0afc4363c4927eb16743cc7f09030a3d4eb4e17af3c31c4269370d43ca7c4f030c43e21ebae144f37667f78862b63ea4e0a2a6b60296b00fe1eb03bea38eabe143c3d216e26a0c449ea2e4b66877b7e60280bfa2a036e606986eb662a7b48667f60016e282bfb0a6acfe6f1b9ae4710825492a7d937212b94a8cf86e711f2b9463a23610f476d0c7810aa87cfbef6e1410c407d3a0b672769b91642a8e781cff627096f0c387b4265e7873a5a357e8caffe4554a297736ec034e6af878a3f5a7d46a4576af87596c38c37aee75f3d827a96fbc5466c50a2775a8d7f3486aae73fa26f709643c4fe557b07276f07adca51c10135590a0a5f5e27d0e8042005bfaf015d3259c6090f5aca01557b6f2707af0fc259015d36590a6fcfa90205577b27595a0e0f025dc131d6c7c09a8c93eb41ebc9d92617acca0fd2d277e7edc4c5520920d294def0d355eb8943d69fc4c29012ec09cbc9df26afc5ea54d2e275d7c726cfaf12cc09ebd9851e587364a9c2debed54207da207e2d6b6203f30c9fbe43d602427fbd25de28c266d985765c1ba8deb82dd67a450722be0b476bf204639b077a25ded02abe4505477424774491d80d7433b43aed5d400356b0b94bff4ecb75b3325c08ec3d459170dc05277744443d0d44755b30b4ea2497407144dc0577b45ae83d75430d34dd9fbd47e3eff51870fd88a7dbddc83a802729c0cd6f763df8a08bcf72ddd83dd855f74df2930af8d8753df8c88aa7dbd646c0f01af51d91a7cbdad8fd38708d22c2e407b9c54b533c8ce6633e6538325ecd37881db5966e332c7925cc596c75e88bee4da0919e56285ca916b33c0c2e9aac53e76ee5819fd616f7156426f9f2e8245f443ff8b9df810318ad60bec8f846def422e4a5c5d8b4b1b48f78c25d32ca5e4fd4279ed044e81490ec52f3cbc79dbc827a846f862e44059c86b81d7e2c"]], [7, ["bafd805cbdec8513cfeec59d523af547ee3acff5c5479d523a47ee9dcf52f5c530f8948ca8b92732f8b9302794328ca8b932f88c30a8279432a8b927f8948c30b9c87345f870924ac870b992734a45f8704ac845b9f892734af87092c87345b91ae3c876bc5812be7e0a20e78f504c730a507e4c2073e78f50730ae77e8f4c20185daf1af71290a3116112c0d1ef3a8461ef113a1284c0d147a3f5f2b9681dea9b2cd2f9c734f1b9719b8106c0295ad69b29715a81d606c029d69b0671c05a81d66618285b53bb016653d6bb1801285b9cf4a36f4b09815ff4099c81a35f6f4b7beae21870a59a9feaa57b9ae29f1870a59fea187b709ae29f70a59aeae2187b3e5240f07de3574d52e33e57404df07de34d52f03e7d57404d7de3575240f03ed0b6f75c2e268d81b626d08df7815c2e2681b65cd02e8df7812e268db6f75cd021facaba4bde2318db24eb9981c699531abb8cd9a62e7ad6f653f92dde962998a431939b9412203e3112a420933e9b94123e319ba49420933e94122031939ba42db14b7f6265e2ab958eb4638d322c788e32952cb478638d32788e63958d2cb44d61ee7ddba837784725fbc0b2a85c2125a8475cfb21c0b2a82125c047b25cfb317e939a0daa26c27eaa312693c29a0daac27e9a310d26939edd8bdcb429d1ef80d7ed991b2001abd7208001edab991b20abd799801b01edab1b2001d7ed9980aa8a99b1714623038a46aa239903b17146038ab1aa712399037146238a99b1aaac2f3179f4c356b72fc3ac5631b779f4f200568d5ef400bc00f4f20056bc8d5e90f995b8dc9f77b83a33c64622c14c2e104ba3fd6c8269134b821069a313fd6c134205eb650b87e2420b138705e2eb6529230ec5032e24f87dda29980e0c370362471d6041091057470962101d576041095747606241101d57410910471d606259a54f42b960dc5cc5bc0519f3595b4abc59c55b054a19f3ab4aeaa548adcbfc7dd21c526bbe0622d2be7d061c22526bbe22d2527d6b061c226bbe06d21c527d4af526288b3044fff5304a4426ff288bba6644590ca847ac66a8ba4744ac590cf864a1b99770b0806470f8b0a180b997708064b9f897b0a1809770b064a1b9f822e358c10025ac62e32522ac5862c1002562e3c12200ac58620025ace358c122edccffb047b8f64fccb8edf6ff4fb047b84fccb0ed47f6ff4f47b8f6ccffb0edab9ade900d2e64de9a2eab64dede900d2ede9a90ab0d64dede0d2e649ade90ababd34696cde583c9d3e5ab8346c996cde5c9d396abcd83468f5b2866508f454e64366f80503a9090363a64906f9080501f3c546341723c373c721f3c543763411a8460d9cb7529d984751a2960d9d9cb75d984d91acb2960d9cb75298460d91af7384c01970de99e380df7e94c9e01970d9e3801f797e94c9e970de9384c01f713e82388f32551abe825135123ab88f325abe88813f35123abf32551e82388132dcc878e65217922cc212d7987228e6502aadfa3e1e2f7e2aae202f7dfe2a3e1ff558f23d75757315557ff578f3123d757315523ffd7578f6658310f6480477f4a9c72b2a9f662809cf64a627280b2a9f6809cb24aa9627280a9f6629c72b24a8210be4f0533756210338275be624f053362104f820575be3326988635efa7a13bab8f4e9ddfbca5abdf3bbc8fa54e9ddfa5ab4e3b9dbc8fa59ddfbcab8f4e3bbb556e54e99fbd9e8a7d185c91cbdbca7dcb8adb18ca5c91cbca7d5c8a91db18952698ec603fc00d263f95c0980dec603f0d26ec9560c0980d603fc02698ec95ae03bdbbaae943e803e9ae43bde8bbaae9e803bbaeaa43bde8aae94303bdbbae3c88cf68da313d0c88313c3dcf0c68da310c88683cda3dcf0cda313d88cf683c079cd94ba30ac4a13649ba2c734808a049483608baa02c7348a0492c367308bae8acc48763661a27ac66e81ac42787636627ac87e8631ac42763661aacc487e8b2e36a5656655aade365b25a6aad565665ade356b2565a6aad56655ae36a56b2dffebbeb49c99b6efec9df9bbb6eeb49c96efeebdf499bbb6e49c99bfebbebdf29df046628a4d0aa16cad73bdbe3fd93cae316fdd7933bdbe393ca3b16dbfdd7af3f4e868a63ddb63f63afdd4eb6868a63b63f86af8add4eb68a63dd3f4e86af4bc97a20b88a6f7dc98a4b6f7a7d20b88a7dc9204bb86f7a7db88a6fc97a204b768ae224e32a39268a2a7639e22624e32a268a2476e339e226e32a398ae2247698785b5997b657fa78b698575bfa5997b6fa78599897575b80b7fd21f2b97d7b38d1406a48a9c862d1a938c840626a48a962d16a3848c8406248a9c8d1406a382733911d769d8d4f339d278d914f1d769d4f331d27768d91253e34efe2fb256f021e24ed44f73bcc1ef7023b24cced44f7cc1eed02443b24edb64e46651c3c428012d8a574123e021212803ed802a574120212a580743ed80274123e12d8a5805b0762f79ef3cd5507f35bcd6255f79ef35507f75b9ecd62559ef3cd0762f75b066a55613e8bf7396a8b06f75539613e8b396a61063ef755393e8bf76a5561069e8b95cf8ee47cb78be49e7c95b7cf8ee4b78bcf9e8e7c95531098e93c5a417af8433988d542da934342f8da399388d517f24516734015b7f810695965c4f1fc67236a14ed508226a8a70dd70b208a66aaf7a3aa87007dfcc7273e4f2f5413b5136cfd2f24c4d6a143900063eecdd20b0be1912bc73f925703a07b370bbdc9df7e40042964503db767c44c95bd90d1f0c49067d14cf095bd42fbcf74f69616733a005e66f5abade184cad5bc64f3e2350e63e33399c529d99b8637a1369be90a1c591764c27f9ef4ca3c5e66cdcdf74a7688328714822374ca58e560708c5d2d", "4ab9eb3cd7171f754ee8f60372f5b217c8c0e05332a2e69e50e6cae033c2a09ec2c8a0e69ee053321f3dbb17774ae9d417eb1cb9773e4bd5a2e2e7c29c50ca30cec1292117e5e24b2ae522cf15e1c349f86a8c23dbf162493f2a40f93181cc9d8140cd299cfb3d32e123c3e54ace2915e52ae1c34922cf15cdf929809c3f42314787bd47e84810028e6274bd6adc4b40e76eb248e71fd3c4006fa6c469055a1b05a6586f1ac4016b104684490047bfeba81f8dd6cbe7a27559c76d061a00a7687e71d28fbe2d250406589b61a06c4ded7eeea98b63c0956a8a977eaa63ecc169ec7dc2956aaa8b636c994d59ef6204a02dd12770068e7ebdc0a997ee698a7f62018d3749c1fbf45d35f94801c1f78d5f0642dbde73b99834de9b04da7241bb344107ba9834dade73f7498dfb5c0135c1fb34f58d5f4901c1b9d89a4037de0772596bec32669bbae86084e82beb2e798ff890c64c6e524a804c4af8c46c92528292fa504a80c44c6e4e6d93ac67061a6760da4fe5b7785ba652c64890824cfa6c353aca54b2d0e28dafb6c42efd899589e03585b9f76da3decb96a01e71ed8700eda38694001fc972e0553ad28e35cab0d0cae0398e5536b2851c95ec03cba2724caa0afb69c6349808c7f84d6a36a89aac025eb7676e8004b483ac5e67026e0402ae6e80045cb76736f8a9c6984c0a6bbf7b762f72d3a6446e5c830006b4af66641a0d28c6aac68d0ca82a66c6c6198dddb2bec4e4d10f5bf0ca0358357ad1037a01d0cb0358f136c6291aa98e640ec4aa0ec4198d2866c6d1bf0cb35ac5dce64d402c8df6b309a6e142e657e2727fde8a4f0815ac972d1ce0a78c38140fb8900cf469a7603a30dcb9e8cc181b890433b32d0942a48d4ef497092d4c1c1688af74245c1d818905415c891d75800525407365953e09e58271ccf366156f152865f3af2aa99722b52e051d258841745c81895d0525401c75802915f31664cc676d70f88a484bf5ad1988f4497348adf91afd2bd59ba02cc210b1ea9a116531a01e3198a1ea1e11b166ad49fbf619708848f589acf91a4873482cd6c3281199fca386c20192e5e25fc202e29385e65ec2c18a898c63050394b06295888d078b00b08b880194b08e63055e92c1e1c38602e6e2035ec2c19285e6038c9788b0628905ffe33e31c3b61fd93fb533ffc31ee1da79af6a7a4336b89079bb786b42ae3690ae7a37b890697a431e31e3b6dbff3fc1b63f1de1da33ffc33668baac92797b431a95274f5bae360f26af4e1b5936970f4292d9bc0142e940dc7cf0508d05c9f105f1c87df050dd8c364f97af0e1a255b393d6ea198413d1642d9e89041be410280d56513666b2ca7646b1082652fd7a57bdee330055c36a4333578e204dc5fa6dc7b5e36a4e330052f13d669a48065676b642fd7a51082655ce234dca73379068d94aca2234ecc47ad4ea08f20ce974489b4301f3a9685e48b0ba87e8f868bdf86ab8a0bdc7f8b8fcea3974c448dac224eacce9744a18f20963187b4e41d8a383d5ec5548dfc5f5fc5fc573d8e5c5f5d012a71cac9a6da8bc9d90372ca2aa58a2a01a6da8b71cac95c575dfd5f3dc68cfd9961c53c90011ea672da2b89c901caf9ce88413c0916d4890942f83e15ccd496eeac3e3a757ef33e7e97ae3aed74f2ed94767ef3ae3e3a1540cc08d6f98a3d86ce98601ad6bc9f75ae7eeff03e963a45f62d2b6e6328737aee56b951a57ff637549a60b283fd0063fe3498b0578201573680fd009b60b22b2bf66170452e6f632c2bf77129466e8399fc54026336b0f5a6a30fecbaaa0ea1bb0ef4eeaaa60f30f0203ea369c7f43cc73020a2f168f7f13068c7f4203ea3aa0ea4bb0ef5a2efbaa2aba60f0df4ee6923c6f0f43c33a0cc2521d920e882b2871e70662f8d2a109ca0b3121f8e9969109b9db01ea28f69a29f8c9969b0121f80da24e9b2cc2121e8228126b1d8cc218eb19aa16b109f1ca995b58e5bc95a69b5ca8eab59599569ba7dfbefae27256fee26bbf9af7f276d7fbb25256ffaefae598d97c96aa9b55ac9b65a95698dab5927f9277f6feebaad6c2b8f5bf45f4feeaba67c1398a19042dbbefe38192a8e753b8dd9fe18be2a76beda2a8e75ff38194f5a285fef6c8ff75f8f4f2aef586cf72afe8cbd763bd91ae929f625832ce1bef52d25eb81e02abe98d8298a938cabe488ab982892d88de7d8998cabe4288a93e0262b2ebde9f5812cf5e12abe25eb818c2baad8e5889b906dd9eae365615e5ee963e26d655dda5e8be14403a921a52203a58a45abe12021e18821a5224703a95de2d9625e6de967ed01def687c8e7f62145a7e2200389a946763ecd749cd8353e9dcc4476d87536300b7890b413ddef90dc337bb40b10ed08b5db3a199571f0d8cd749e34463e75bc95f8d0bc8bef971379dc0bec9030b7604b08489402d2f908004a6097d249f8576d1d88dd7bce378bcd571ddc6f79366f5579ce371f88ddd2494800fa600b94020ad049f84860977b1ecc6f358b55dd572de6a88519f8dce718a85585f92cdedd7a2e563e3b92f35592df2e3e7b3af2e94d4160a6f36805f9a82d1adc57e58419e4f82cdeab55853b2e927bf255de3edc5ec81759cc01554fe20fe520560b699a9c8da851b44309f1abde8faa1e02f4d41e9ff83cbd504d560f09e16be74c22f3e343a4659511c79aa19e365c2f80285e2d8447ae1cff48874eb0f5bf90105bdcfa0111a49041f5f612439e4533c157cc09ed3fd3d95b5a2f0c41028cb9374b7f0f80eedd2cf426c39f113355f64246643b8c8dcf6416a786eb007899d5afb6d273645d9009ff79d0d921ca1c52088eb528639583c13176d7102a57f392cd8b2b6c1ade84da6ca62b29f378993537df", "7b2203834fc9889ad429e5aef35c5f7cc90823839a7b824f555fac73e4def92cc3888a9f0b7342295e38a1db0fc8d5cb7a42992b83cf0883537ff4ec5edc29a525e1ab318e6cc78b2f3907a7845c948bc8040235a770eef75794ab840f27893cc534e7a70072fe0827a9948b3c57840f77fea800e5c7043254848f0c972b39a7139fbbc9229d7f4c081c1df61ea12341ac159862bd691007d6a17e345a2f9f8ba2651db71968009c01398ad1f5aa712f6d00bc9912a71568ae43181126011cfdaaf9b9a72e8e015710f8c5493ffab6948eb1f70957aaa92ef5b6449fc01938fa8901a75ebaa729feb51b606d8681b235a7295efaa98eb10780b2653665bd8b11d218086d7bcfe562770534de2405efd3cf051de862d2687b04efd3d4377e2505c8e5626b02dd781f7ed5e4230504df37d2786f1268cb05ed04df2735ee7305d401e2431a33b94929a267adb1cb986deab949ea43290112339982693f95dfe26db3491923410a32e93d8211a2afacbbe4093229e113b3494a9c39b54db29e19687a83d714e6deb78d37d6e82853c9428bcbb58f1a52027c24c8422b83e73856d9ca157254b20f2c8b26beda12bbf42756022c5b827ac4b51fc38257e9483bd62812b00a78dd9eb9016032a92aeca719d39e09b8ba011270dd12fdeed9bdc84d9b9ab9710d0218d0be6a221ce337a9d9a011d00eb27a9d09b8acd9e0a71a6332296c75cbfa1293473f37926934a018ab1adbe805402f0f60c519ab3a106734a2989b47ff32cc6a15733432a0aa98191b670fc02b0f60d5e845101ba768a43a923970283e2154b05eb6983601b134dacf267033d0a79d82e9c0d1cfb6240891363abe5e26b43071582079870b995f89cbfd42829f32e2503ce0cce4a233636c2412c6cd9555fa24940b04d1917075042616baccbfaaa45e8ad401267615940071d4b5a554cc5b90319f00712576d40116949431cf9b55bc55a0051674942006d17143f4af546f82b20866c0e12b222dd5b79ac56086aa7b44c421d527b2e66b20cd8fb2580fa34464f26b20d227cd21b5e67ac4aa6b4694c58022b526eddb67c021c22a26328e150c50091b0a0748968b7f152c220650c23a8e9a8b0f7809074b16160c305e22c28a25070b884f169a7b09c08a5522361e2c02987b4906870f1b0a42e6bdaae90dd9e064ff8ffbc40cdb7e0db9eadde042a6e90fdbfe74846bcffc0dd9a0e9b24ae6ed6bffd4cefc0f7b8440e6ede2ad09b9da047bc48cdb6effff03094966f30608a53c68549e3c6db9da3316c423f7c1437558e4f4b8856206f5090865a34306f9063e98bc3a6d64d95cc773f3c1433516246cd93c5dbe3a689490ee798fc31470d99c0256974d98adb11470ef79d9908ec396ad91bd5c974208197089d3709fcee49792ad410896bd5c99ced4e08913707f9dbd4c58a79102969227d2c27ce858161f3552b28a8e38313e1aae2a2e70ff2d8238b13a5f12853ee258c61cd292772812b53a813e82385f7e2f2ea0fa3d1a2e8a388f5e321135b22f06a8c429279b6a7df578155335f27f27ab04986a2fc62978f4678615f34006289bca69af2426077515f35ff538727d2a26670fc829ab9433725d75f57ff518cd5bbab3fae8d4f950e73b2306f12458e8b453daf9cdbbfa7e1a3a63826958f3ead4b9fabdc3fb5853272608e1fb5430c9fbf85dbaeab4d3f65400312358e72b03dc506982c90ef6cc15d9b7acb88da1c95ed900f6036c82b98db1acdcc7a518c00e66f253098cd9d9ebb95be54695fe068cf9d360c25e09bcadacd887c115b9d3c3c083f88ca61d3ad49b8e3eb0ebaa8cc6c3a01dd383f8bbeb8aae9a3e34d080a68d18c3d3f3cc3e84ee3ad0bbab9addf31cc38088c6a3beab3a90ee3ad48ba67182ce4a7c3866ca3297846483a00b7c887e3266a6c14a87a08b049ac462337238c66a86ae417c401c7ac099bd34aaa6416c76c27a883e84006a93a4cb3287bce9f6edbfbb9e94a5a556d63a6e256bbbfeed9694bce9bf6625db6a55a635aeb69ee49ffcbdb9eba6d52a3bae666555b4b99bece6bffe9d6a65355e26aba5d6d66dfbfae364a838b9b3ad3c6ed17f3d64f86aab38d6fde3dd7f3d3ea9bc63b16ba8f833f6daed640aad9af24d608642d8ed3466fb63f8aade3f69a17cbdb33d926362a7284e32aefba6a7d8970cb2844e626732ae92a32807b2d487abf896ac4232aea86297236ef8d6b794ac0782ab9e23ae62a248623707829bacb8f4a6d78a2c86130da4869479b565ab8f978579a4862386948a1c0ddbb70778db1f229fa686149d8a830c247ba58f89b7957569840c942a16ad86839f7589678b79b5a5bfc32ce041d24e74d718d9f934d37162c123d46eeb6454c65ff256e243f32ebedc4ee4712fb043c2d9f8743213d961d7b44372cfecd12e40d46137d379d218f9df5cb5752076ef39e7832d2120510a4876bf55e539df7c205d0a284027e1238175ef7930bfd52c56e1230028815d4a27d92c365f7570bfe5504a272101e8832dce77ebb958f9ec48735fb598a31666e015a437058199cea3156690e3b378af56fbecb848eec95779789f63a05615e6b3c857497ebbf8ece913e6a3b668705f9525687236a246d10e54717b215f64310735517b7ce2f3f4421ccf8f0f91965546a268867ada70bd00a43d893f9483582dd0c7af7a3faa7a0889583d2484af9d33d573eb07449042062379b5101eb972fc693127b4ff4c676f9bfc3d00ba77b3d0190d7f46cc54d90b6c1d3ac1d6ff42425fd94b0c7916cd042cbd30040930e6dee749cf91754126fc9c92ed30363e9359d8d5a28c550e06c799aeb06978136ab37cafa4cce365d6dcda1aae03e06556bf38426787287348212f5e43a85ccd4b36", "3e25238c0c6aee096aee890c0c3e2523a50c232a7e2ecc090cea0965ae0c3e23944efdd1b37b71a7f151a794bbce737db3547db1ce917be72f7be1846e3f2057df231308d49cc2b92f9684afc638b21d2314d39c9f02c8f9c8dcf9a302941f139c52113e325caee42ebee41c9c127251f25c51ae123e9c243e9ca4522ef25c111cb056608af5a641314d7cee268b74fe708a9675dc66a001a0b501f0664a9c56f4bb0e614498047004217074d87b848e2e5a87fad168bd7cbd04e42846d7abc6ba38c6de275ca9a65ca9e6e79eba3806f827069c7ae99ea61e9ca678e9a73ac64600ca96d994f52e5242e01727fde8dbe8d7db127d0267e0d6d46e80b51906caed3d1774a08b49a38b496320b4ed3d977d20978bad0974e3b44be3bd49a02d1750137c9fd4b8cf154fdf15d0789314bc1410bc4f53dff895dff855938f14107ccce426a90fa50448a504880f69cce426a4cf26658c0429c82925c8a4844fcc26a071e6d436c97a66a98b9eb5c62e63b6b7650aa6fd547e8b92f7084688beb2ee912cd73e6a4809f036ea0d5e53987bdf2c2a57c851c93eb07e08b06c09ea11d7a30c0b5ea523ed582dde58a3a34c250b65230bad0c9ee3585899f86a4becd29f757b26e0ea0648c00648c02ae0757be6fb6ae6c635086040e046403bc8ea7526a4b066839f6a8cc94c83c9a4aab09f666d4af4bb67f7223783aa89708cdfa466156fa31700bd3c80fdb0d52deb4b4c1ecc6d1efdcb30ab55173d00af3c8055a3e6406c9ca291ea486adc48a6d18062ac6266acea409cd1889cd1c880aa62666c03c3cd409f760aa6d9c2a1f88450c17a81f87a99d0c2c461800b097eca8843f14830938bce8cb1919b60da04c4d2683fe8443fdb922044daf7e71d2e647e252e52eb32ffaa927a292e18375756e993507cd69652316f41c68152c63c6f56f156c71558d05182184458104447c2d51198510798d8555002c45002c495d8510758116b168319aaee11220cd1bf52bd09cac93fca623d8c129103ea11abae1951168788d49ab46f9f01df9a0187af88b4543487549fc89aaf819aaf81489f3487d43856b088184009eb4009ab98c8385630965830c07889082b08002b5689d878b02860ee25191c3e6cfe256c281c20592e59682e3ee0251c2c251c2c203e5968eea637e4aa77830b99830b99f7aaa63764b7376483a6cb2a996a0399b78bb726e4ff13ec11336ebbfdfb91fd3fee13336cf33f6cfbd311ae3d11aefd533bf33fecd5cd58108fdc070f940e242499cd1b201b2420948d0e19e4901ccfcd070fd55851b265f374f9eaa06af3a05179f2b4e5d46391d3e3168a1973f960f2eab491650e53c0bde765433a6543bae73d0e53c09367c0254ec37d3afd653a5383274ec05876f632619d460ac6720a585d3661b62158b646f6725d0a725d4ab6062158f6b7f868b8aab8c0fd59489e480bf3a163a188631973484bdeb8f8bdb880eaf768c82ae23c7ac944d4c47cd448c92a3ae2fa08e2c4ea7c49147c49d4ea04fa08e2a79cac1260aabd18aabd18a012a79c6c1ca06c2aa7bd929852aa989c3d20a7ac63ccc875d5d5ffd5fff5d5e3554cd5c819e0d19f1956cc03f5d555cc7fd5e3c8eaa3d34e69e737efe7376fe9ceeaa35363a953e7eaf70eef4e27efe377e9aad3afd85301c48c609d60419def8c18c493cdfb69e88c09a661c14c9d982084ef5309267b6503d80fb0d80f7043a509263b66033b98c94f2530251830e64f83097be4f2b6b2621f065786325764dfb2e23662e436c6b2721f97fa67afe76e951b55e2331a0f83764c0f764c0f030fe2339a33039a36620c4fcf8f76cf730c03221a2ffaaeea40baeb50abea506f3afac0ae40efae2bba6afad06afa10baeb40efae2bf121fac99899069899c6093a2bf1e1f1c9e118ab19ba06fa9806b1d909eb211c1202a84d922ecb2e28cb5c12920d82cd1c822e1268128ba80271e80167f6d2ffeefab75b52f2a652f2a6dbb7ffee7aaedb7a927ff2f7e677d2e66eb29bfffa5aab95d57899ac96ac95965a59ebb895b89a956cab5599d6559956abecb89a958f93e1abade258f7e258b7edeb8f93a193ada1e2cfd86bb7ab62b7d398ed8fe1f678ffa485f2f5cef5e4ceb6f2b845ffc576fff5f8a4f28e0a29b46aca378119a238899dc9b84a8eb84a8e899da238c9b809c9b8a28a5d8edd788eb88a8922895e1f086eb2e2d29b12ee9b9e625f32c8b21ec8521faee25baee25bdf52b21e0834901a8e18522a72522ab2184e34901a90981a52742a0e320e123250aa58b41a967ed6259e2de6d5e6e5d596ad3e5e167c6edf1ee06d7f88a5ed953e26de56d619078f50bbad9351d1fd0eb38007493b09733b91c7bdc00e00d10ec93db347bbe45387dd4ce74963895d6364e7d34cc7f87ec95b890fcdbb5d67e3d3c94c648781d8fd5695e77cf3e77c73d5d681d8bd58d5bde7c1fc56b39667b3d87cd5c1fdb640299d8404a00f209d0fb684804429047629a0009d848f9d848f00a00476298f5690de1404663a2339dfade762e5b3e5edb3e322b9275fa7235f25f9ede2b3554e988fdaa2c17d81cf7dd5628e5a985a5598418ecfe2bdcfe27d8e815a55980bd544edf189cfd33b94a0c9d9881a450288a219ea69c3f521401fbfeafda8eace2462f59010be761c50c5ed857c91c519713c3f3e445a56b590f624fe500e62bda5c59cd0fe339d1954cfad1f10410a2f6434fc19315365137c652f31e459347bb3f4c21024c098f18fe4d54278e4ca426ff2f700e8decd09b175e8045bff0b1c63578b32563918f09f273d47d6059973f3bd92328f975985e0089d1da2cc21d9bc780da172352f66714ab6c3d8f84ccd66bac2a6e14da8fd6a6bb80e809759", "2794328ca8f8b93027f8948c3032a8b99d523af547cfeec59dcf52f5c53a47ee5cbdec8513bafd808ca8b9273230f8948c30a82794b932f8f5c5479d52ee3acfe78f504c737e0a20e77e8f4c2050730a92734a45f8c870b992c87345b94af87045f870924ab9c87376bc5812be1ae3c84c2073e78f0a507e45b9f89273704ac806c0295ad6719b810671c05a8129d69bc0d1ef3a84116112f2b9681dea47a3f51af71290a3185daff9c734f1b99b2cd25a81d606c09b29713a1284c0d161ef119ae29f1870eaa57b9aeae2187b9f70a5bb1801285b6653d681a35f6f4bf4099c285b53bb01d666181870a59a9f7beae2187b709ae2a59fea6f4b09815f9cf4a38df7815c2eb626d08db6f75cd0812e2657404df07d52e33e575240f03e4d7de3f07de3574d3e52405c2e268d81d0b6f75cd02e8df72681b6f03e7d5740e34d5220933e9b943112a42031939ba43e94129981c69953db24eb2dde962998f653f9ba4bde231821faca9b9412203ea431939ba4942093123e31d9a62e7ad61abb8cc0b2a85c214725fbc047b25cfba82125638d322c78958eb463958d2cb432788e7f6265e2ab2db14b7ddba837784d61ee5cfb21c0b225a8472cb478638d8e329501edab991bd7208001d7ed9980ab1b202693c29a0d7eaa31dcb429d1ef9edd8b9a0daa26c2317e93991b2001ab80d7ed99801b01ed20abd79a310d2693aac27e5631b779f42fc3ac0056bc8d5e00f4f2239903b1718a46aa238a99b1aa037146b171462303aa8a9979f4c356b7ac2f318d5ef400bcf20056b1aa71239946038a8705e2eb65420b13980e0c37037dda294622c14c2e3a33c669a313fd6c4b8210b8dc9f77b890f995eb650b87e2134205c5032e24f829230efd6c826913104ba319f3595b4ac5bc05a548adcbfcab4aea101d57604147096210471d6062574109604109105762471d42b960dc5c59a54f5b054a19f3bc59c5606241101d0957474426ff288bf5304a4744ac590c66a8ba061c22526bd2be7d06d21c527d226bbe526bbe06227dd21c288b3044ff4af526590ca847acba6644527d6b061cbe22d2ac5862c100e32522ace358c122620025b0a180b9976470f8b064a1b9f8809770b99770b080f864a1c10025ac6222e358c12200ac582562e3b9f897b0a170806464dede900d9a2eab649ade90abde0d2ef6ff4fb047ccb8edf6ccffb0ed4f47b8b047b8f64fedccff900d2e64deab9ade90ab0d64de2ede9ab0ed47f6ffb84fcc906f908050363a643c543763413c721f8346c996cdd3e5ab66508f454e8f5b2896cde583c9abd34680503a909064366f6341723c371f3c5496abcd8346e5c9d3e94c9e0197380df7e9384c01f79e970d2960d9d9cb84751a298460d91ad9cb75d9cb7529d91a846001970de99ef7384c01f797e94c0d9e38d91acb296075d9847987228e65cc212df7dfe2a3e1aae2025123ab88f3e8251351e8238813abf32588f32551ab13e8238e652179222dcc87a3e1e2f7e202aadf8813f3512325abe8627280b2a99cf64a629c72b24a80a9f6578f3123d75557ff0f6480477f66583123d7575731ff558fb2a9f662804a9c72b24aa96272f6809c23ffd7578f573155bc8fa54e9dabdf3bbcab8f4e3ba59ddf75be624f051033828635efa7a13326984f053375628210be4e9ddfbca53bab8f4e3b9dbc8fdfa5ab4f820575be336210c0980dec60263f95c02698ec950d603f5c91cbdbca8a7d185c8a91db18cbca7d54e99fbd9ebb556eec603fc00d952698ec9560c0983f0d26db18ca5c917dcb8a3dcf0c68da88313c3d88cf683c0cda3143bde8bbaa03e9ae4303bdbbaee8aae9bbaae943e8ae03bd68da313d0c3c88cf683cda3dcf310c88bbaeaa43bde9e8031ac4278763ac66e81aacc487e82763662c734808a03649ba2c367308ba48a0494ba30ac4a1079cd98763661a27e8acc487e8631ac46627ac08baa02c734948369bbb6eeb49fec9df9bfebbebdf6e49c95a6aad5656e365b25ae36a56b2ad56655656655aadb2e36aeb49c99b6edffebbebdf499bbbc96efe56b2565a6a65ade3dd4eb6868a3f63afdd3f4e86afb68a633bdbe3fd9316cad73b16dbfdd7e393ca6628a4d0aa29df04868a63ddb6af3f4e86af8add4e63b63ffdd7933bdbcae31639e22624e38a2a76398ae2247626e32a6f7a7d20b8c98a4b6fc97a204b7db88a20b88a6f7d4bc97a24e32a3926768ae22476e339e22a268a204bb86f7a8a7dc9c840626a48d1a938c8d1406a386248a9575bfa599778b69821f2b97d7b80b7fd5997b657fa98785b6a48a9c86238d1406a3848c840a962d1599897575bb6fa783b24cced441ef70246651c3c42edb64e8d914f1d76339d27efe2fb256f253e341d769d8d4f273391ed44f73bcc021e24ed02443b24f7cc1e1d27768d919d4f33cd6255f79e07f35bcd0762f75b559ef33ed802a5741212803e12d8a580027412a574123e028012d8f79ef3cd555b0762f75b9ecd62f35507a580743ed81202127c95b7cf8e8be49ee93c5a417a531098f75539613e6a8b06f76a556106393e8b613e8bf739066a55cf8ee47cb79e8b95cf9e8e7c95e4b78b61063ef7558b396ad70b208a66a8a70d4f2f5413b5c7273eda399388d54342f85965c4f1fcf8106988d542da93f8433914ed50822667236aaa87007dfcaaf7a316734015b717f24595bd90d1f067c44c74f696167342fbcf63eecdd20b439000370bbdc9df03a07b2f24c4d6a1136cfd2964503db77e4004d14cf095bdc490672bc73f92570be19166cdcdf74aca3c5e60708c5d2dca58e5bc64f3e23584cad5a1369be90a9b863766f5abade13a005e64c27f9ef41c591787148223747688323399c529d90e63e3", "17774ae9d41f3dbbc29c50ca30a2e2e70372f5b2174ee8f6e033c2a09e50e6ca3cd7171f754ab9ebe69ee05332c2c8a0b9773e4bd517eb1c5332a2e69ec8c0e0e54ace2915e123c3809c3f4231cdf929cf15e1c3492ae522f93181cc9d3f2a402117e5e24bcec129299cfb3d328140cdc34922cf15e52ae123dbf16249f86a8c490047bfeb104684061a00a76859c76dbd6adc4b408e6274c469055a1b006fa647e84810024787bd6f1ac4016b05a658d6cbe7a275a81f8d48e71fd3c4e76eb259ef6204a06c994dee698a7f62c0a99761a06c4ded06589baa63ecc1698a977e8fbe2d25047e71d2956aaa8b63ec7dc270068e7ebd2dd1278b63c0956a7eeea9fb5c0135c1f7498d4037de0772b9d89a01c1f78d5f35f948da7241bb34de9b0449c1fbf45d018d379834dade734107ba8d5f4901c1fb34f5de73b998340642dbac67061a674e6d9390824cfa6c52c6482beb2e798f6084e8c46c9252824c4af832669bbae8596bec4a80c44c6e92fa50e5b7785ba660da4f4c6e524a80f890c6d28e35cab0e0553aec03cba272851c952efd899589afb6c41e71ed8700cb96a054b2d0e28d353aca94001fc972eda386398e5536b2d0cae0b9f76da3dee03585c6984c0a6b36f8a90006b4af666e5c834d6a36a89a08c7f85e67026e04b483acfb69c634984caa0a80045cb76702ae6e2f72d3a644bf7b76b7676e8004ac025ea98e640ec4c6291ab35ac5dce6d1bf0c66c6c6198d0ca82a58357ad103f0ca0328c6aac68d641a0dcb0358f1367a01d0198d2866c6aa0ec4c4e4d10f5bddb2be181b890433b9e8cc4c1c1688af97092d57e2727fdee142e638140fb890e0a78c8df6b309a64d402ca7603a30dc0cf46942a48d4ef4b32d0915ac972d1c8a4f088841745c81051d251664cc676d2915f375800525405c891d156f152865ccf3661d8189054174245ca99722b52ef3af2a25401c7580895d053e09e58271736595f619708848ad49fb281199fca32cd6c37348adf91a88f449116531a01eb1ea9a484bf5ad1970f88aea1e11b1663198a1f91a487348f589ac9ba02cc210fd2bd5e1c38602e65e92c188b0628905038c9785e65ec2c102e2938d078b00b062958892e5e25fc286c20194b08e63058b8801c2c19285e6e2035e63050394b08a898cb6dbff3fc11e31e3ac92797b433668baffc31ee1da3fb5336b42ae369079bb7831c3b61fd9ffe33eb890697a43ae7a37e1da33ffc3b63f1d7a4336b89079af6aaf0e1a255b364f979041be410242d9e81b5936970f26af4e508d05c9f1dc7cf04f5bae360f1a95277df050dd8c05f1c8a198413d16393d6ebc0142e9404292d969a48065672f13d6dca73379065ce23482652fd7a5646b10e204dc5fa633357813666b2ca780d56536a4e33005dc7b5ed7a51082656b642f30055c36a47bdee34c448dac22cea397b4e41d8a389631878f20ce9744ad4ea07e8f868bdf8b0ba8a2234ecc478d94ac0bdc7f8b8f86ab8a9744a18f204eacce1f3a9685e489b430fd5f3dc68c5c575d2b89c901caa672da3d8e5c5f5dc5fc5772ca2aa58ac9d903548dfc5f5f3d5ec5da8b71cac92a01a6c53c90011efd9961cac9a6da8b012a7108d6f98a3d1540cceff03e963a75ae7ef83e15ccd4890942ae3aed74f23e7e97413c0916d4f9ce887ef3ae3e3aed9476601ad6bc9f86ce983e3a757ef396eeac6170452e6f2b2bf654026336b08399fcb951a57ff67aee5698b057820163fe342b6e63287345f62dfd009b60b2573680f77129466e632c2b60b283fd0037549abb0ef5a2efaa0ea4f0f43c33a06923c6f4eeaaa60fa1bb0e20a2f168f73cc7300fecbaaa0ef5a6a3c7f4203ea3f13068a60f0df4eebaa2ab3ea369c7f430f020e9b2cc212180da24a16b109f1c8eb19a662f8d2a10871e70b01ea28f69109b9dd920e882b2cc25219969b0121fa29f8c26b1d8cc21e82281121f8e99699ca0b3c96aa9b55a598d977f6feebaad27f927ab59599569b5ca8ef9af7f276dee26bb8e5bc95a69a995b5256ffaefae7fbb2595698dab59c9b65aefae27256fba7dfb5fef6c8ff74f5a28bd763bd91a2afe8c1398a19042aba67cfe18be2a763b8dd95bf45f4fee6c2b8f8e75ff3819beda2a2aef586cf75f8f4f38192a8e75dbbefe2ebde9f581e0262bd8e5889b908c2baaeb81e02abef52d252892d88de788ab9825832ce1bee929f6abe4288a93d8998c2abe25eb812cf5e18a938cabe498d829625e6de9675de2d9e2200389a92145a76d655dda5ee963e245abe1202103a58ae365615e5e6dd9eaa5224703a9e18821f687c8e7f6ed01de03a921a5228be1449e34463e75d8cd740bec9030b71379dc4476d875363e9dcc7bb40b10ed90dc33cd749cd83546763e3a199571f008b5dbd0bc8bef97bc95f890b413ddef300b7800fa600b94d249486f358b55dd7b1ecc6097d249f808004a1ddc6f79368bcd57489402d2f9604b08ce371f88dd6f557949f8486097020ad088dd7bce37576d1d1adc57e584f9a82d7bf255de3e3b2e925585f92cdee718a82e3e7b3af25592dfa88519f8dc572de660a6f36805e94d412cdeab558519e4f8563e3b92f3dd7a2ee16be74c22560f09365c2f80289aa19ee520560b694fe20f8faa1e02f4f1abde1759cc0155dc5ec8f83cbd504dd41e9fa4659511c7f3e343a851b443099a9c8d028cb9374b2f0c413355f64246c39f11f5bf90105b874eb09e4533c157f6124347ae1cff485e2d843fd3d95b5acc09edeedd2cf4267f0f8011a49041f5dcfa0157f392cd8bd7102a78993537df2b29f37899d5afb686eb00ca1c52088ed0d9218dcf6416a7643b8c9583c13176b52863de84da6ca62b6c1a5d9009ff79d27364", "db0fc8d5cb5e38a1ec5edc29a5537ff4aef35c5f7cd429e573e4def92c555fac834fc9889a7b22039f0b734229c3888a2b83cf08837a4299839a7b824fc908238b3c57840f27a9940c972b39a754848fa7845c948b2f3907840f27893c5794ab318e6cc78b25e1aba70072fe08c534e700e5c7043277fea835a770eef7c80402d1f5aa712f01398a1126011cfdae4318f61ea12341081c1d345a2f9f8bd6a17ec9229d7f4c139fbbb71968009ca2651d9912a715686d00bc62bd691007ac15986d8681b235b51b603665bd8b1180b265493ffab69410f8c59fc01938faf5b644a72e8e0157aaf9b95ebaa729fe8901a7faa98eb107a7295e0957aaa92e8eb1f7230504df377ed5e435ee7305d404df27de2405efd3770534d4377e250504efd36d7bcfe562d218086b02dd781fc8e5621268cb05edd2786fe862d2687bcf051da2afacbbe43d82114db29e19689c39b5b1cb986deaa267ad3f95dfe26d9982691a33b9492901e24323410a32e9b34919e113b3494a0932294329011233b949ea12bbf4275626bedae9483bd628c382572853c9428b37d6e883e73856d9c8422b14e6deb78d7a83d754b20f2c8bca1572827ac4b51f022c5b1a52027c24cbb58fe337a9d9a06a221ca71a633229acd9e02aeca719d36032a9d9bdc84d9b12fdee78dd9eb90112b00a0d0218d0be9ab971b27a9d09b811d00eba011270dd9e09b8aa98191b673432a068a43a9239101ba734a018ab1a379269106734a29819ab3afa1293473f6c75cb32cc6a15739b47ff0f60d5e8450fc02b402f0f60c5dbe805995f89cbfd79870b33636c2412cce4a2b134dacf26983601240891363ad1cfb62154b05eb670283eb430715820be5e2632e2503ce042829fa79d82e9c07033d076d4011694007125942006d171051674707504261604d19115940071d401267655fa24940bc6cd95cc5b90319fb5a5549b55bc55a09431cfaaa45e8ad4baccbf27cd21b5e66b20d2eddb67c02122b5262b222dd5b766c0e1b2e66b20cd21d527546f82b20843f4af0fa34464f28fb2586b4694c5807ac4aa86aa7b44c49ac5604f169a7b09070b8806870f1b0a987b490748968b7f091b0a7809074b169a8b0f328e150c50c22a265e22c28a25160c3022361e2c02c08a550650c23a8e152c22cefc0f7b846bffd48cdb6effff047bc4fbc40cdb7e64ff8f74846bcffc0fdbfeaae90dd9e042e6bde9b24ae6ed0dd9a0e2ad09b9da40e6eddde042a6e90db9ea3a6d64d95c3e98bc5dbe3a68946cd93c9e3c6db9da3c6854b8856206f558e4f466f30608a5030949a34306f906090865c143351624c773f323f7c143753316c4410896bd5c9792ad58a79102969dbd4c974d98adb19c0256bd5c97420896ad918fc31470d990ee79d3709fcee4197089e08913707f99ced479d9908ec31470ef813e82385f12b53a5e321135b28a388fb28a8e38311f35523a5f12853e8238b1c27ce858169227d21cd2927728e258c6a0fa3d1a2e7e2f2e2a2e70ff2d3e1aae5ff538727d7515f375f57ff51833725d155335f27f7df5788615f3400678f467c429279b6a2f06a869af242607289bca0fc829ab942a2667986a2fc62927ab0408e1fb5430532726312358e72bf654002306f1245850e73b63826958f37e1a3ab3fae8d4f9cd5bbafabdc3fb58ead4b95dbaeab4d3c9fbf8daf9cdbbfae8b4535be54695fed9ebb9d887c115b9bcadacb7acb88da1cc15d9acdcc7a518b98db16982c90ef603dc50f253098cd9c00e66d360c25e09068cf900f6036c82c95ed93ad0bbab9a3e84ee90ee3ad48bbeab3a8e3eb0ebaa3ad49bae9a3e34d0bbeb8a83f88ca61dd3c3c018c3d3f3cc80a68dc38088c6a3ddf31ca01dd383f88cc6c3c099bd34aa401c7a93a4cb328784006a846483a00bca3297049ac4623387a08bce4a7c3866a671826a86ae417c7238c676c27a883ea6416c3266a6c14a7c887e3bae666555a6d52a5e26aba5d66a6535d63a6e256ba5a5566a55a635ae6625dbedbfbb9e94bce9f69ffcbdb9ebb69ee4ece6bffe9db4b99b9694bce9bfbbfeedf24d6086420aad9aa17cbdb33dde3f693c6ed17f3db9b3ad3ea9bc63b1dd7f3dfae364a838d66dfb33f6daed646ba8f866fb63f8aad8ed34ab38d6fde364f86a94ac0782abf8d6b7acb8f4a6d707829bd8970cb284fba6a787abf896ac07b2d4a7284e32ae926362a86297236e4232ae62a24862379e23ae32ae92a3284e626789b79575697ba58f678b79b5a59f7589ab8f97857979b56578db1f229fdbb707130da486948a2c869d8a830c24a686142a16ad8683840c9486948a1c0da486233213d961d7d9f874d379d218f9d46137f934d37162d718d9e243f32ebe5ff256e041d24e74bfc32c712fb043c2dc4ee4cfecd12e40b443726eeb6454c6c123d428815d4a27e123002101e8832d504a272120510a48e7832d4027e123815d0a28752076ef39df5cb530bfd52c5675ef795f7570bfe5d92c36e539df7c2076bf55a05615e6b3789f63b668705f9513e6a398a31666e0735fb5e3b378af56156690b958f9ec48ce77eb48eec95779fbecb87ebbf8ece9c85749058199cea315a4373f9483582da43d892484af9d3389583d215f64310754717b0f919655461ccf8f36a246d10e2568727ada70bd00a268867a3faa7a08d0c7af7ce2f3f44235517bc1d6ff42426c1d3a040930e6de2cbd30101eb972fc2379b500ba77b3d09bfc3d0744904206d573eb46cc54d90b190d7f0c7916cd045fd94bb4ff4c676f69312703e06556bfda1aaea85ccd4b362f5e4330363e93599c92ed6978136ab399aeb091754126fce749cfcce365d6dc7cafa487287348213842678c550e06c7d8d5a2", "94bbce737df151a7846e3f20572f7be10c0c3e25236aee8965ae0c3e230cea098c0c6aee093e2523d1b37b71a7944efdb1ce917be7b3547d2a7e2ecc09a50c231c9c1272512ebee4522ef25c113e9ca4afc638b21d2f9684a302941f13c8dcf908d49cc2b9df23133e325caee49c5211ae123e9c24f25c519c9f02c8f92314d374d87b848e0421702846d7abc6bd04e4ee268b74fe314d7cf0664a9c56a0b501608af5a6411cb0566144980470f4bb0efad168bd7c2e5a8775dc66a001708a961727fde8db5242e080b51906cad6d46ee79eba38065ca9e678e9a73ac61e9ca6de275ca9a6ba38c696d994f52e4600ca127d0267e0e8d7db9c7ae99ea6f82706d0789314bc4fdf15938f14107cdff85520b4ed3d978b4963bd49a02d17b44be374a08b49a3ed3d179fd4b8cf1550137c4f53dff8951410bc8bad0974e37d2097b5c62e63b6a98b9e4688beb2ee92f7080f69cce426a50488a4844fcc262925c8a90fa50448cce426d436c97a66a071e6a6fd547e8bb7650a658c0429c8a4cf26a3a34c250b2dde586a4becd29f5899f85e53987bdf36ea0d6c09ea11d77e08b03e6a4809f0912cd75ea523ed58a30c0bad0c9ee35865230bc851c93eb02c2a57a4aab09f664c83c9708cdfa46683aa892ae0757be60648c03bc8ea7526e04640e0ea0648c0757b26839f6a8cc9a4b066bb67f722376d4af4c635086040fb6ae6a6d18062ac6adc4880aa62666c9cd1c82deb4b4c1efdb0d5af3c8055a3173d001700bd3c80156fa39ca291ea48e6406cea409cd1886266acfdcb30ab55cc6d1e04c4d2683f9b60da2e647e252ef7e71df88450c17ad9c2a17eca8843f1800b09409f760aa603c3cd8bce8cb191483093db922044dae8443f99d0c2c46181f87a47c2d5119858104495d85107585002c45756e993502e18373c6f56f1568152c6ffaa927a2952eb32d051821844c71558d8555002c451079852316f41c67cd69687af88b454df9a01489f3487d49aaf81bf52bd09ca220cd1abae19511603ea118319aaee11116b169ab46f9f018788d49fc89aaf81348754623d8c1291c93fca281c20592efe256c203e5968ee251c2c98c83856304009ab5689d878b008002b88184009eb3856b025191c3e6c2860ee3ee0251c2c59682ec07889082b9658303fee13336cfb91fd533bf33fec11aefdf7aaa63764830b99b78bb726e46a0399aa77830b99a637e411336ebbfdff13ecfbd311ae3df33f6c83a6cb2a99b737645179f2b4e56af3a0f2eab4916573f9602499cd1b20940e24cd070fd558901ccf108fdc070fd5cd58f374f9eaa051b265d3e3168a19d46391948d0e19e41b2420585d3661b6c6720ab6062158f6725d4ae73d0e53c06543ba5383274ec0fd653abde765433a0e53c032619d460a5876f646f6725d0a2158b6254ec37d3a9367c048c92a3ae2c47cd4ea04fa08e27c49d4480bf3a16359489eb880eaf768b8f8bdb8aab8c0fdb7f8683c7ac944d4c82ae2c4ea7c4914fa08e21973484bdea18863e3554cd5c8fff5d5cc7fd5e3c8f5d555a012a79c6caabd189c3d20a7ac52aa981260aabd18a79cac75d5d5ffd563ccc89f1956cc0319e0d12aa7bd92981ca06cef8c18c49360419d982084ef53c14c9de9ceeaa353e7376fe377e9aad34e27ef4e69e737efeaa3d301c48c609dafd853e88c09a661cdfb69e7eaf70eef63a95364dfb2e236863257e76e951b55fa67af43a509263bd80f70e64f83097b2518306503d80fb009267bb2621f0657e4f2b6c6b2721f9762e43698c94f253066033b6f3afac0aeabea50baeb40efae6afa10030fe2339a764c0f730c03221a8f76cf0f83764c0fe2331aea40baeb502ffaae2bba6afad040efae36620c4fcf33039a5c12920d822e28cbe80167f6d2a80271093a2bf1e19899c6b1d909eb21fa9806fac99899062bf121a84d922ecb1c12022e1268128bcd1c8218ab19ba06f1c9e15a59ebb895ac9596abecb89a95559956dbb7ffee7a52f2a66eb29bfffa77d2e6b75b52f2a6ffeefad57899ac965aab956cab5599d6b89a95927ff2f7e6aedb7ab6f2b845fff5e4ce6aca3781190a29b4edeb8f93a1e258b7d398ed8fe1ab62b7abade258f78f93e1a485f2f5cef678fff5f8a4f28ec576ffe2cfd86bb793ada19e625f32c812ee9bdf52b21e08aee25b899da238c9b84a8eb88a892289dd788e9dc9b84a8ea238896eb2e2d29b5e1f08521faee25bb21ec8b8a28a5d8eb809c996ad3e5e16e6e5d53e26de56d6a5ed95184e34901a522ab250aa58b41a0e12328e18522a7234901a259e2de6d5967ed61ee06d7f887c6edf52742a0e3290981a64e7d34cc7895d63d3c94c64875d67e3b38007493bd1fd0ec93db347bb00d10e50bbad935119078fdd4ce74963e453875b890fcdbbf87ec991c7bdc00e09733bb684804429209d0f00a00476299d848fd5d681d8bde77c73d87cd5c1fd9667b35695e77cf381d8fd9d8404a00fb64029a0009d848f047629e7c1fc56b358d5bdd5628e5a9881cf7d8e815a5598cfe27dade762e5b32339df25f9ede2b3a7235fde1404663a8f56908fdaa2c17d554e98418ecfe2bd5a5598e322b9275fe5edb3ed857c91c51c50c524fe500e62b590f6c9d9881a453b94a0bfeafda8ea21401fedf189cfd30bd544f59010be76ce24623f3e445a5619713c19ea69c3f50288a2d54278e4caf18fe4e8045bff0b09b175ad1f10410a1954cf2f31e45934137c659cd0fe339dbda5c5c21024c0987bb3f4f700e8decd426ff2fc193153652f6434b6c3d8f84c66714ab80e809759fd6a6b3d47d60599f09f279d1da2cc2185e0088b325639181c63570da172352fd9bc78c2a6e14da8cd66ba92328f975973f3bd"]], [10, ["5dfe402ede76c289e777e2ce291dfaa3290041e734e71844e7004434e718412942ab04d8234bbb80d8ab80234bbb044223ab424bbb0480d84babd8bb048042231a3188e6216811bce631bc216811881a21311a681188bce62a124d53c3071ea12df272c0ecc98356c0f256ecc983722decf22dc9837256c0c9f2c08372562dec1ea00bddce8ffca38b8d4fd02ff7d6d0d08dd02ff7d64f8b2f8d8bf7d64fd0d00a2f65eb1c915d65eb2f651c915d650a1c2f0a915d6565eb912feb5d65650a1c7f79ae5a2c8c9b225a79222c8c9bae7f2c797f8c9bae225a0756d71059f430fcfbcfb927d021a00ecce06bccb0fddcf1cce0f1b0fddc6bccb0e0ccfddc6bf1cc9f18c5d837e853d8d818d837e853c59f37189fe853c5d8d8e818d853c5d89f3786e6a6e682c94c94e6e69482c94ca686002fca6fcaa6bb2c6f2f2ccaa6bbca0096689f67099f9b5c67685c099f9b9f960968969f9b9f5c679f68679b9f5c96092f59f4f50b9543fef559fe0b9543f42f0b592f9543f4fef59559f543f4fe2f0baa019b16673454fd1601fd6734549baaf24254c10d65f6835e1e15044aafa007619bce950c7ae61403048f93268151099304092681518f0326040381518f0993c948d2dbb50c36b1db48b1b50c36d2c9b548c90c36d2b1dbc990ecde816911ad12f5f3a303d6f703a3f50303d6f7f31203f512d6f7f303a3d6f5a3f7f30312034ddb831a6f9116db1adbdb6f9116834d6fdb4d911683db1a91db1a1683db4d6f34eec0265ffeee1226ee125ffeeec0345fee34feeec01226feee26eec012345fc8830f7dcf7c7c4d7d834dcf7c7c0fc8316d084823e17983486d8323e1790831a6df508f66bc374e8fdf4e66bc3750a666dfa6bc37504e8fbcdf8f37504ea66631b770486a94024048b7406a940270315de797f2ddd6fc7ff2e77fddd6fc975df10e9239fc100d8c390e8cfc100d92f1fc0ef1100d928c39100e390d928cf1fc251e05be6e2b758dbe1e8d6e2b7505256e1e252b75058dbe2b1ebe75058d256e035d66fa551c7255fa5d55551c726603555d031c726655fa1c5dfa726655035568d9db04d6ba8cd904d9d9d6ba8cdb68d6d968ba8cdbd904bad9048cdbd968d69b4ff83616f04fa932f570127c9421f3bbc7060c865de4130cc713865de406bb2daf14c32863d368c3af682863d3142d28af2d63d31468c3d976c75fcfb145fee842aafbae9eb92cfb422cae9eb9aae85b32fae22d8bdf40e232402d8bdffa5b5e2eaa58e3a1cd46582e46e3a1cdaa5ee32e5ea1cdaa4658a12e58cdaa465ee38c84c6bcbc0b32bfbc84bfbc0b32c68cbc848c0b32c6bfbc0b84bc32c6bf8cbc7837ae95b27d571a95371ab27d57ae78b237787d57ae1a957d379557ae1a78b2dffd3cb6bab5db48b6fd48bab5db3cdf1bd38778717a165578d355717a16871badfe4bd9d4e13a77d9fe77d4e13a4badd4feade13a4b77d9e1fed93a4b77add40e41034f731901894f4189731901030e73410e190103894f19414f0103890e733e73bd2f7cb830092f73097cb830bd3e7c733eb830bd092fb8732f30bd093e7c67d2fb9be5b9097f9bd27fe5b909fb67df991060e805a6a16099a1e805a610df4470215603062b0256700203062b214498a23be39228f931e3a2319228f93b98998b434e123bc1a1052675ec962079d2ec26d296207975053036da64095484ef2a00b4051824cdf60500f61824cdb42a18002a24cdb4f605240005cdb4f62a1845083cb5f18d5c4cb5084cf18d5c3c45f108458d5c3c4cb58d08b55c3c4c45f118a8c26a757650c56aa8c5757650c21875a8187650c2c56a76a86a50c2c518759c4a4c2a1bd1381c2a4a1c1bd1384c9c1b4a9cd1384c1c2a79207afa8904e9870836449ce704d74b00e773ab18fd3d28b7cd6204e6ec4b4c04cd4ce6ec4b62b70bb4d2de3e0695a1deb4a13e0695d20b00b29ed49ed21340d4b2409ed2139e007912ed8af5cefac08a12c0f5cefaed79f51279cefaedc08ace128afaedc079f517dddf457e04831645dd167e0483df177edd170483df164504dd4583df16177eccfeb2c2238f10da89b2deeec3f65e87eeb287c3f65ede89eb0544945a386ba552c8183fe149b5293fc829e149b51852e1c85249b518293f49c83fb5182952e18a8093818f6a8ec78180c78f6a8e938a8f808a6a8e93c7816a80818e93c78a8f5dd3450c347a31480cd348347a31455d34d35d7a3145480c7ad30c3145485d340ace8cd0124e3a0fdf111e0c4278f4fe0c11fe4278f41edf4211df78f41efe0cbaa10d3315adaee433a1e415adae0dba7f2f296a2f6764b26a2fb22f6764297f232480b04f9b9b3911290a5a3635641022dd0ec839deab1cc8dd1c39deab0e22b111bd2207ac10ff2211ff07ac10bdb13124d5bc3260f1eabc24ea3260f1d531d9f035797ff88a8679f0867ff88a35d97ff0d9f88a358679ff5c693784b7fdaa30d4e8f5c6947698f5d498c69476e830f3b020b6abe650ccb6b0ccabe65020f3a9aef8f1873e87f4f1aef4873e87f8a959d86bb7608f163fb7d83f608f166b596afe18817bf4e65481fe547bf4e6186a9daaeb0ab263a0670aaa67b263a0eb9da8285a9aa8b098469a2846a8b0985aa8d3dc4ee419a412e1e4dce119a4124ed356891da0bef66cd1a089d1bef66c1d5669990f025ce12a6f02996f5ce12a0f690d20c84f6b9d04906c8bd220260048d50f7c03f6d0c502439e6dff36f4be226736e705a933cd767d582b9dc27d8bd95d3c33dc067f3fc9d95bcd9951e1bf1eb5f2876eba6c226645ba87456c22666ef28bb3153a228945fec21aa7fae2f27504b2719761324bf6e60da046bb9a4861deed602ccca4a8c57f2b65d69765b351b5", "0085469656b177093af447cfefc49d530900b14756859676ed8413bbfc815cbc318252ce018868ce967601855609b047760984b057014796ce3188520082ce69ac5ad893e58107e5221035cc637843d0e5ac80d9e55b9207d02278356210cd430f3c4255249aa6869307ad5ae4e580d907e55a80e5add8931079cd436234d022ca1438225fd6bbcaeeada1171b9fa05fcacad6395e1422bb1ff9473d4017ba9d9fa0a15f1a17efad22bbca145ecad639bbca14d65fca3822ad9f16a11ba15feed7e29961c199fbb9375dffb4f2445818b9d79899c1e361fb183745fef25cb558e861f80facae21b243401df69f734fa0fbb9e399c1d798615d45b458f2fe1837779501de5e58944da78a3fb131b06fd04d7759005e94df94d0a7b03f318ab16fb13f6fd031b0a78a9399280dcd4dcd05994c0dcdcd2905938ab1b16f303ed1a7fd5f162ab3ea87e8373f2dcfd0b8123ee8fdeb17b25e2a873e37b92cd13ecf12b92c133ed1ce363f2a87fc5fb2e8eb1787e85feab3fc172a3fb9ce12d02c3f371e13264d080602a3a836552d02facf68a31e072609124c0268a8fa5503362dce5e410fbc3c2a0894f4cc29c2369d2b1902a31206081e274dcaec07e585a8821b072406aceb47efe76ca493b791626b19e7074607ea25acef196c629391a4b76bd3225a9321d9bd03acef0724eae74707efe72546eb0706aca463b76b9192196c2568befcdd4ddc812d069b34b6b7df2281254cbedc69fcdd222db69bb60735deb79bde22b7352c06fcdd2568dc814dbedd81694cdc25befc06b735deb69b222d9c4ccd78bf1f6fa0f81e90fb069b9ef9a09c1ecdbe4d796ff9f89a90071ffa9ef3106290da0647c2786f9c4cbfa11ecd6fa04c1fbf9dcc78c2f30663da10904619e3f9211c721a2405e062906e81d428241973f81de2211a280580626ee190d4f92fbbe4cfffbaad211a18e31d2473f81a24e3731c18f921adf9ffbace2fe5bbaa06aa38baf4e5ccea0a4a7c3d1add56ccaaf4abba0638e456ea1a4b3c0a7cdd1a4bdc563c7ceb0a38e4aa06baccf4abe4cc06f4bbaaaa380a1a7ddd3c4a56eac80d76198e270cbb19b7d108b2b3ad75bbc827768f0d180c7519b3d1b2b709acb3d1ac75b30918b7e09f52379ff06d2c2843e665eae124f8b7b309acb3d17419bff5b7c465805a16a6295a865fd150c616bf81b664f4c55bc6a6d15a5e298651638bfcb3ed8ebf9e3d7359d08554f75d7355d1f785585c3d29d086515e5bc6a67f1979170879658c9b55bdb05c8cc6438c7f797909191764439b8dbc5c54b1c68dbcc6435db09a5517647e19098d7979648c1979097f7917558db0c65dbc429b2c0e37f0a6abe2f4ae5cf12a6f3464fbf42caa36a60ff1e2fbae34f06e5c2b6535f064fb6e2aaf5c6bb791befb796c75b779be6dfb91746b5c352a656ff0faae121de632829e020675965ab3fdefa8c306129fe6821c3202c375ee5afd97b2a9ee5aa9c3fdb375963202121d82069ee602061c9e8212e73296eeb2a9fd5bc3754c21bec13243d10b617a7d5ee612f8700b4c43bf3321c0d07061127ce67a5ff8137cf870e75e607a7313fecea4f737cb13f6cf36a5ffca737a135ef8e67c7061a808df616cb4c912564288ace004060cf2ea0ad84da42d410c560488e042ac06f27730c7456324517682433317879c2441f2a40b4cead82d51f263304577c625988ae21b116ab9789a69550a00ec314878986ae3118a1ab9489aed5500680b30ed553048000a9a691bb9988a10786ae3b9788a6a1198e21b69ed0b300054489a09d20ff340f4f413a08431d4508bebec983854369438a371eca08a315085d5ea8b31eaec50d5a084a27138389598543671983855943836a2848bd5ea5031eca0273c01a865813ca5fa7b5000cee75631a5278000643da93d09ae97106c8838cf97c46e099a99ccd90c2a431768a5bd7d2aa517bc69437d0cd997986e9bc508cc2d2efc08ba8b06bff5dbf3142580eb9dbf2d8afcba2f08069df581f324da15eb81f3ea9d2514f5db08062d2ebabf8bfc06bf2f8aba2dfc08db8115eb25f29cf552a4c293907f6a31edbd0e1365bddd8731527ec291a5926a1e21b499fd65854770d64ad70b8828b5936a53a490317ec26a31a47e9053c293bdbc13dd650f87ed90ba68f4a619628a1c271503018f1fd58a901868a6bbf462d51c8f150127031f8f151fd500031d27f46290baa68b1868628aba18a69168f4278f031f0115d51cc852fed45e645fcef0e8fdbf233c1884cec864ff5e52d45e9c741e149c19a1253dfc198422bef1e85a5dc975431b662a5d1b746742c92b5ae83dbe1922fc85f0e2ab637849d465c06ac820225214b46cc0e2d56348aa7965363773464800619f571d4490bb3972bc5821fe63237a450e217a634522fe0f58bc573944ba1d9073a140e66d619957cd156bb2f3e00dfff0cda198e761416c57f0150db3e16bf2fe6ffb55ffb9d26e0829ed3061a8d1eb8dedd061eaa9318d296b0cf3fee0b3f11540d73b1554cf64c70ef153e35de90f7dc740cf3a55d715647d0ee9535df1e30f2dd6b26eb17fc01ee8cda9d4fc3102f7cd31d402fda9f6e81e2d7eb2b0d76ec1551ed20432dfb8c231b55035518c5061c255ded2321f04b861318d5051b43451259ca6c9b9c33348edd9a2ad123b407dd93aac4013a37ded4825c2a7b99dc8337f3d6ab79a33a3c20090aad916a5414c7e92b37966b80dfe3a09201b40909fd67d45ce3cdbfe6de89aedfa6cce0b526716b3bbb0563a85fb8b05861ef806eca166a36a57caac2fcbccdce4750f8bd844518bffdac158984944cc8ae40fdd74d9e5eb0884354ef5c596eccd65e32ec36491c2bc1b408d7635128bfc17672b7444", "049dd39c6310a500893ba774e88f9edf028e2ced120861af62ef12000a8d2cad03b978db092776f910d19c6304a59c0312608f2ced020aad0a2ded1200628fac68a04520f29a87c4f086a045206a98c75bb1270fcab500cb030fca59b5b027cb209a87a045f06ac4344d0d1f7884aa48cb01b3270f5ab5c8b7240fca5901b3cb42bfdc5b3f2d42373e41bfdc5b432f36947144769529acbfac779595297044be2e743b3ff28f7a802ede5b3f4143bf3494ad7344769529bc2844769595ad73bcfd316eba8a68b1e489b0306ebafe69e5af31c3f673c7338333f773afc533c382b96ab1306e8afce55d4364d1c3f01f58e79e4087803aec3fc7c3f673af3133837ca24f156363df6060dfa04f157f6263530a2633991a9a9bb0289bee2a03bcbd1463dfa04f617f62604f15637fdea0639b9a0b2633511a9a28bf299beeb200bc597e6e7e729d25a071257c6e7e5a9ea1f92f540ed1bfd467d50fd1fbbf2c54667d9e257c6e7259a29d6d7e7259267ca2d1d72f540ef9bf64bd540ed1fbd72f6451053794d90fca0bf49fd1506daa5a043c4e9a0446250c100c04463d264c9a106c5a9cd150f5ab06541028bd821e78793a5732e89953846d249804463d0e4c122533d848c76ed722c5d632d848276f230f0c58dfcf4b8cd68fdecf0f480c58d7496fd732d8c42623b27b07a645b42643cf8f0e58df0f48d44b58dfcf0f8c0ed437455a0c6e6bbc6d6fbf455a0c36696c4b7cf9bb03d398b89bb8034bd07cf9bb0f6abc455a6c376d6b580c6e37bd456e039b7cf9bb4bd0b8d3f8bb034b987cb921208d84e70dc6b4363df3f13d20f70d3b99f1de40993e7e3fde4039999af17e3ef43df3f135210f0d8e84e721c420b5433d9af1de38997e9bf2de40393d9a7d5fca775bf3ff759d02a9510ac0c520dd30f2433448c6e738e4344832c6f34338c221a9510a00c5dcff755bf35f76c99f48e6f0433430c63bc443344832e6f03b94acd41534faba7934baadd41594f87a555571c8990de877e9cb99550d54717414f8baadd4359678f8d6153496b8ad7899e95771c8550d740d70c89955e95775a3e9326e67135867675beb326ea31164c349f05186cccbd44f1876911bec321c6f1358eb3266a36513306e67a359eb66e1db58c03fa56e3e1b301876914fec1eb68c4d53a00da3bca2a18c4d53b40cbfb1b87ae6aaa2ef0b00b52c7eeb6f89cb520ca38c4da3b5bc1d7f3dc716f967dba9eebb7ae6b2a00be88bb72c7e036dc9788536ab1a618dbb188d8736ab7a61b9fef22ec81833f212f2ca18ff32f22e10a8628d87361b79b96035ab1a798d87ba1af3f22ec8fc3212322ec818fff2f212e0f55db96a54cade68c8f65db9e255de23e9d66ef37cdbf657c5e9591c6ee04db856caf65d69e0dd545eb96ae0c9f6ddf3d8ead66e237df71fe2c5e959546d4cb786eb2cdd6553fbdf5187eb2cb566fb25ce65040c383c053d050c243acc65042f655387ebdcb5fa67eb2cddb55287fb0d3ccd6504243a043964040c243ecd05f9e0c2f426bcf0cd25f0e1c2f4fabcccff95e726ec9f6d4a86a21798427c8365f5bef0e1c224f8ccbdc0f426f8f0e1ceef6f96e726fc9d494280a11798867e67ee8c4ba2e4c7608a090c18ac841059c1d4b15b82e44917986893255011bec3d885580d18ac0810c1c648a2e4ef608e8b0e3949ec0487662e485b82e4d515b09ba89034d3da176000d8639034d3aa140030c53772f114d522d472f13015c53722d016609034dbab001434d3daab609000f0d4c63772311521143572f130d5c62362d8410917abd5a116d7d9410963a8a1716c44e33071aa28e8e92712a41fe6810aabd5d9411563a0aa41091763d4d9a131a96c44e370702a7146e33071a86c288b1198b32f31dd36cfad62f4f7a0009c86fa18544a2f78d302794a4f780250cb10719e135c2f21d83399b32f89dd12344a7bfb1854862ed07a527b4a4f0001c8e439ebb7032bd64b00d73bebb7e7294a5bf8110c7e5f1475170d7e5b5cf81174b42bd63beb03e74928eab703e7d53b4b7f17f9110c5a5c745f100c7e5b14f9751e0edb7b7927bacb7abb0fdb7b1d26caa78427d56248fd20ffd462a448852721cb0a8f3c426833fb10516ae1ac95ae1763fc8427d5a648214b25d562a4fc84232aaa394e1e073e021e3faa394e2a060223d1e8c51475314c33c4142175d1e84d4e063eaa391e2b02063a4e1e2b3eaa011731d0e8c520754d77e9c5142131d04cf80be1d17b7c3344783008e1d1fb7f479257b4ba36e8ce84c8be9c91a5fca9bd33424b38e93c28387ce3d17bf833084536cc54b4ba92eb86a4a8bd9c91c9febd3b20e778af7288742868d9d4904144a4fc1fb042f4c68a44a8cb80c557c7f09200c23e6d6ee68c9073e478af3a882077f48a1cb042fcc74654f3ca80c5abc79067e32bd618e6fdc11bfee12bd664e7c1631a53daa1c3d45332af9a4381ccdbc2d7e4fde12b1a66c3a5dd10def6abfe73a3d71b53da61c25082d8ae9a4331cfc3afdd823d5afc6461d21ffa1ce2a7c6bb53edd19b63a805fa9ec98e81ae772aa8e2c71ffa1cd2a7baff803d5aac65dd626304eed19b53a9f9ae2bc88e819e75aa3b9167904a844f7318a1c2626aa16aa246fbdab375588126be7185ab3ca409646869a2c2621aa1a28767904a384d93737680fadab3455b253e087085abbca5650dd843170b0c3df04a8398002055b32d740af72d667761ad674685ff7ad46e35203fad7512403680fddbd0fb8a9c79b617a4ce34dbf5d99c701bfcfd2467f3cc56e8882416f92fce16b18998b9c9eb1e1aed6a2285793780595f96cd46d5ae94bae9b2899815c91f9cea8bcbd711086b5d86c92cd99bcbc6b13093a216ffb583", "c41e59155ada25001f3dbf13774ee9d005145a25c01e59da204a01083aa739c71a595ac5de2500144eecf20772f1b6134a390720a239c70810c25e051c59da250266976f491e94b3d4308fe10d418b40b46a919703664f1e350f89d1408b40e4614f96071e94b36ae0d58841340f418b085591689a1a3ef06b0196b7624f1e945be7785188ec2a2b865e6c7c827eb9b72a5378295be788ec5a846e847eb9b77ee0887c59ef2a2b531ff5005de8767ee4867e695cbcb77e8253587f29e388ec2a6366068f87ede75efdd3ca136161dc7475d87fce3d810e01d162c9fb63dc741567860567eee75e8b14f9cb73d56261dce13fb0ba86c8a2878e67065f6386ede7650178517e5336ddfec4c6c0be419f2aa234343735174c66c6bec1f8449f2ac606787b615136dd55c2fec428c6be419fbc41c7c09e2ac6fe353437a7144c6632af5fc87aa91ca2f7b43c43e34af8dcfcf27fc9a2af5fa81c3a4b40b3fcdcfce459a8ccaa1fa2f77fe4b244fb3c4bf8dc4cf8443bdbfce4b27fa9cff25fa81ca21c98244830098c7a54b508e83fa3a1daa708db74ae64d0331f9417a20a6e28b398342118088c7a4cea570dd8b438a3a13df0f2a820507a054a1820789c34098c181da897b0be9f1f4ede468aad65b0911f90a89f1f1db0beddae454a66b0918e18b0ae1fbd9f1f90894d4692deae65b0684d8664f70e4c8b9718ad1f18b0be9f30f972a7f17707966cd2d8de7e8bb41897a0710736f9f277d678db6e8ab418dcf9f27737710796a0d86eda1ed4788bb47a8bdcd6b018dc6ea6317197f8f277077a34fb36e5bd817240ee1b6c7ae6e37b7132fd867a34e3bd1b8c6943401a09cf35e3fd7ebc8172326b421e7ce87be6e388416a1b1c09cf43327dfc7632e3bd81cce17788876890648b41ba0552a31480608c7790cce18768ffeb3abf94efb6e6e78770c86990648c008ab9854352a314ec923fffebb6e6bf8ccf7160e4876890d2afea1ae09033ab28f1f568745ba92bab1ae832d3afe290f475f32859a92b68a8e2e8d29733ab1a6b2cf128f0755ba9715bf1f0ad2b682c1bd0efaaaae290339fd83d366030ec224623c8ceb6d665dc4add7cc2b7b1807f26b0ce46d365dcced865389e30ec2237cc46cbde26b0d665b3d6cd2660dcce469997a98793e0a30c06da92d1176f59fc68197e4543199ba665411752dd77f5cc1b46796d199ba640df1297016a59fcd6466b79a51846199bf2cfb63bfe7a8e2d45df176271f5cc55e5e525645c9031fef5c272311a0f6d56f9652434e6e55d90c21a77f10a6d5635e45d20e49531fe6536f27251c51a0f6d1a0f75c16a5635f266e425fce55d9031a8da983ec48bd3b3c5abbcd190edbb7246faeee7b1d5addda894bdc1ebbb72d5dcc09bae8ad3b338d2c0bb71ad94edbb93edbba9bc72d5c0f9b6ed47d2addde67c9a0b72c80818486acdf6bfa30ed7594874081a789acb08cba6f66f0dd759ba98cb087a0a184874b96bf55fcaa60ed7a50ef7cfd659ba6b70780a4a9ccb08180dfdce8400432f30f579994be0c385e9f83b93dedf2ccf4d78e19bf3c185e94df806cb0c452f308549f099eb7de1c385e1c39d7b81e94df03fdb94fe2bcf4dd82b603791b604c9ab21b28213183058090ecd5c1c7292d8098fc114dd199744c97c87b1d1264ba0221120820bb11a3058c11c178d9144c9df932e30a963b704c9aa8d47286ae4e261552900b0c72069a6622a42e0a98d6fe42fc000502169a6b58a6f44a8e5e2612ab65701a02dc02069c120012868a6b55729aa45608a6fe4e250d950e28cc661e2c650432daeb38312e1e0546252d988c656ab43c5b083122e3fcc03d1d34f24482ac6401556abb383a8b3435583122ec6e25451e2d888c661000290f5a4f6949e4101389f5bc5e8ef0c5da095f6f631a862ba6d162330675f04a09605f2949ef05e42b021e23c27b8bb25686632675f125ef0a60df531a89428f2ebbe2018fcb6cf539400ae77d66fb4b8e8fe2ef2231856ac97c873d66f07f023e82e1afcb6b807ce936857ac77d6ab779650d46f07cebe28eab6f02318fcf90947964aaac5483a4c94f5761fb6f74d9142c6f8094faa4e74973d1cb6f7f20a4f42fea9c54891d066f697151e79842b5d2f20a2d4c25990fa414e094faac562a099eed28b2942540c043c7e54739c41ea9a2e62a0d18b0e7c045454739c3ca2d19b66882942ea3c56049c0c7c54737c54030c749c3c56ea629846a2d18b2993fd7b49517b3923f7ff8ef06010c2a325d70d6d98a96875f86688f017c2a3f7f9537b917d39234b79507066849670d267108af8c6a3f7f0d09d0925af68756d578f21a9e695018b83884851d0b2a921f88f8de815396085e510e97640cef15e8ee1255197018bafcc192101847ddadc1041eee6c8f15e758d1589f83f6085e8629e8705b15d3587c9ce8337fcc357acc384a146af37a6b4ccfb83cfc657ac3199b785655e35870234cc86afc9fbc35757fde74abb21bced87a9a7c634a6b4433deb545d57901d034f8d77a53ff439c4a752f3c708dca337f8c9c25ebb057bb4ef54503d931d035da44f75c58f3ff439cbbac5fe017bb458500bf4a7daa337c7794bcb7c10e00a5742d544314285c5d48bb64aec00f5b567089fe67622cf20954813c87ce30a5779344245d1d24485c59a26e70ecf209570b0024d8cf6b567ebcee699e136f8fb49aa665b9406310140ebb3392f489d69b6187ae01bb0872e16a8dd6ace8c0afff5806c00417e5aeb2439f36cfbb7a1f715eec25ae914ee5bccfe6b07636126452d93d73d2c6213317337978dbb0c9359b2f25f9cadd011492caa5d29b3be2c9b8d2b923f74d36513312310d638d51797aff36e0035dad5440a", "b2b44b2084bd0a389cd2a13f7a7e27ee738e1194720e4044b44b00883db22ab44e738e41940210744b002834b2b48abde26d279cd8e50fe43db2b40b28b44a809e3c28d7022c6fc5821681a8611ec31b357ce011aa22d1343c286705cc2edf921681c86b1e12a3812867d5c29e2c0f3c1e8216c1ab118368cc9e3c68d5222f0711d955a6b0fe52c6fd726f0dbdd8f8046ffd040dfdd2b878d95556b6cef1a210726ffdb408dd08fd5556a6c011f9b2deedfcc83fea01bad0ce11d955a6f052b60cdbcf1dcf0cbec6c2b8e9faa79527c291450fc37f60750ddbcfbdc6cc0c1e0fb8e92aa2c592f7c7cfbd16cf0c0bcedcc5c2b829f297e7aa021d02eab0ff9c7b98cc646a686e4e29833e55fc898d817d558cfd79838e813da66cbacb02f0a2fc3e558c8d7d83f1896cbaab0cf0f6c2a27d833e85fd89518c2e98cc4469686e6a503944ff529fe5bff0b9f9697986c695f9c96599f08976b63944ef5fbf90f552b9f9c975968066f944efffb25099553f96f0b9c96589f679bf5039e4ff92455f691218953040f0384643b5a96a11d07fa0f40a7ae0e551411218f53830499060dc50663f282f441518f5983069423010714643d5af1ab069c9a0674e11b6e95c607d3f2f315a3f30cb60239dbc8d145b1d9816d19a0cc9ee7d3f3f303a502f6160231dbb5d8b94cc3f3f2031605d3f7a5dcb60139b8c24bd3a607d3f20513f3fe5ef0e4c63e22ef1166931d8a4b1bdfd31b8ddf416b9ad61ef0e2c61f2e54ee36931b8adf1b6dd140e2c41f3e5ef6ee2f11669b1ddb43da8f2e5ef2e41e30e6cc67b0365faf8ed64ccc7f780dc37d8f4129e871083d436387b03e5f468f66dca34129e3718d3868003e5646ac6fbfd78f7ccc7d7843cf8d068c67be364fa0df50fd120199fe3c0c84629001783740ba46dcd7fd9257ffed7d120c998c3ef100fdf6dcdffd7757e2920c918cf0fe190d3a446290014730b87c30fd1c018ef2099c5216736a0df5555b6525750e2ebd1e857d058e2b6e2e15b216756a55fd535c05257d0e8ebe651b267563550c5d1a52febb652d758e251e05fc5215735d065a6c14719322f530f27adcbb88d46909d6db89d8d66ad9b4dc060d8453eb17b6cc0cbb89d4d609d8da6d8456eb0cb703c6160adcb988d96bd4d6301ff94baf9846fea99ab8abe2fc4e232364dd132fc8a86f51c5be49f6d77fcdeb2f80db425a32f364d81368cf2da32b2f8adbf252e03d48c32368dd6f24a31efea99cb822ea4babb2063ccc84bf8cb1edaacea85e56234ac6ae4351eea82d52063fccbcb4bc8b8daac6a8435eee21563fccbc8bb40c82b351eda6ce4e5a28acbbb20f3cb4868cc5bbbcdf36ddb8fa4db77e58a5779a321e5aa8127db77537917a76751b5317d8877e5aa51297b83d7a76771b881375d1529db77a58177e35aab5bbb8df4ddcf63971130e0f01494381daeb3d49aed7f47b374d74a1dee9fad113090f83417e490aeb374974deddf1a3090e8309711f4144d1dae73d7eabf9434971190e81034f09e9bb07fb629fd57870bd3ebf33297c0d39be0c3873bf702865e601afa9d09010bd39bf0c237e7835e600af10d96198ac2870b93e033d7fb599e9bf07726bdbf6e0992275d6052c760b01242640527308992bf83392e1a2309925757c06e226d2e89921f8329ba33964045f80e63a34d3560b0224004176224b1131c9ab938e4dfc8c553548bc01441d24cab5200608f4c6baf82410250d0c8c5c3541b8f50d4d24c6b5f8001a042c5c35414df8850cb8041d26caf02405b1bdfc8c55484c053118dc3c4a9a2c4b16707258ca1865a5c255c8c516787aa068dc3c4a1b2a1c41907255cac56878a619f48907e9807a2a7566707558c812aacb2118dc3c1a9c4a4635029bde04d1bea8ad1df8302703eb7cebe24764bd0cc64ed293d010420eb4960cebec474db2c46293de109402d0be4794e70bd846043c4ed635019ba402bed4730f87d51d46de1efacdf9ea728015cdf0e9c57ef2ca1a830f86d51e4d77d41acdf0eac582f91e7f86d71e147d05d3458efac0f9c27d1aee447306871d1fd5d9e548b21f5839c123e6cef759828ebeda985b356ba5e4044548b91f2138e2c956cefe59de82e7b388b9122159e84fc533cf208a1cdec2f2b139e549b22858cf1a31753d4c5308d44a8e638a9180878fc3879acf8a80618e8175384c44033dda5e638791cf808a8a85384d445a337cd10f8a8e678ac08381940a31783d4355dc4d1eadaa03b134a5e208447efff1de1c147efe1cf2014f18df6724626fbf792a28447eff1cd10e12f724696f2a7f622fb2de1a4f3a0e0cc0853d1ea4aae1bda30c00ad11b2b12f17f655343061191a2a0e3bdea2082dccd912b0316af1e4352cd9ce3bdca21d2ed8003165f1dc34ba22efbb4b9993342020872c00af11f1bd12b4c69870e534f8d6987af58939d076ff84378dbaffacf9576bb6a0ec53c0f0b62af586398f7079f8d6a0e05326f0bcbbcf787af68980d5f936f4c698709438d5e476f8ea116e84fb5e873889f1aef4a7ff668b196758bfd03203b067ad6a9baae0bf668f19385bd763b06badea9a07a267fe873489fea8a1fb8476f4ea5e68f116bcfd661059a18ed0a8ba985aa896284412ae1344dce1d9ec015aef29696f9209e412a113ecded4415aef2902690f9c6890a8b69848aa2a5ea6bcf166d95d801dcb798dd85b5d22962028054cdb6280d43ef2b72e6d9f66ff0f7939ccd33c36d0f5d2c30f4c0376015feeb51bbd59c19b4d64900d90082fc3ad36cd767735e90ab8914e6dd006ab42662e626af7b58c42f2e5f4720ac71aa4c8a5afcd70ec6c2239258e4bf385ba159361b55bb52667dcb266256247fe8a626b3646f2e1b7719", "6895007b64691750fc4edc39a5437ff4cb1fc8c5db4e38b17b15706469974008645568699700107b0520e89ce61c832869157b97005068641c8088e61c2328e5455e0e983d79d0aa3c8637042d0251c32306d13c042d825758de8a3d7950ae055dbe257950ce0a982446032d0291d73c591e7850ceaa853d45a2696af8c02354e1a56c9d23b2ab4cb1f109fae5de1a7a0374a1dbf9917fd4fda58c23b2ab4c61e34521b2abac6c9dba11fae5defa6911f265bdabac4c8123a571f1defa091afaff39f7043a04d4612b4f848571d3f54f2fcf558b857153e4197c8d19b69f3b9e193c1eb69f7b8d9925ef8f71d355448b169cb99f7b2d9e19c0ea1a228b1e86ffd0dcd45c309989d21b03fb067daaf81313a318fb067d0afbdc9c523099c9d4d0e045f94dd974970506e3137daa181bfbed8545d9745719e01d037baa18fbf306258bbe7ea172c8ff0c8d2be173f3d3f212edf32ce17393cb3ecb7fa17288fea521eba57288debf7e01cdf273f393eb2c32ab7e88deff65a113ed6cf393cb32e16cd3b99241cf9c2222a0ff8c866a53d53560d3e28c86aa5f80e071d224302a619220c12430ea71605e882ab8a1cc7e5084602030ea3161d2cba38240e915f4c0a27e7e74c0fa7e401b29b696c1463a7919497abb96c12636b47e60c0fa7e5e62a05ec2fa7e7e6074162999c1463a76bbba7ef47e7e4062c01992dd3b302da235c61dd8e4cbdf5d82637bfb2dd262b049697b50e32dd262bbc45de2cbdf1d98c6cb9dc6df1d58c2e46dbb29d262705be3dfddc41d5882e6cb725bc36270bbe92df41bead18cf7c6c96fb0e9998fef01b979f0a1ef998faf09f1dbc98cf706caf4ecdb94f706cae9d1a60d0169243c6f30f7fbf106cac9d48ca96d70243c0f2106de4132871fa28131e916488d52002e06e6160e498d520028c781911fa241323edf211ea241923187ebfc52bedb9affafc221a74192319e1ffefcafdb9affb24ba0cb4cbf8a43ae6ad7a3d16da5aea0c4c4a3c0d76da5aeb1bfabaa8a43ce6c40aa6b8043ceac4abfcda364a5aea0d1d7a34b5fceac6aa08ac5c3b7aea0b1c46df309dfc602fe2975203bdb5a97711b8d2d7b9bc05a97311ba61e4e828f32645ef7d880c1b08b7c623a1b4d97713b9bc0e178c2b08bdc6097379b80713b1bcd5a5d4875dfd5339705f8150d656c9aa265e5956218656c1aad5f88c5d53357157d4b465fbc65f11b68e5b5656c9a026d185c06a865f15b7f4bdbeef8eb39b6c83f91d098977741e697cbc5683cb459d50bcb45156b3cb4d9c897f0977741c6989197907141c6f89797dcc52bb459d5086b819057c6f8979177d405ab59d5c86b3cbb9fc756b7761be9f24643b6efca15afefc6b552b6ef4a03b61f49b7769be7db63fa102f4ecfa26af606afefca55a3526fba2a4ecfe27003efa6f2ca55034fb62168e0692e2320d1dbff8e3a5c67a935d57f299b3a5ce7ae2928712e2360c0e12ec821236020f169dabf355c67e92e9b23e8296020d1612edc3f5b67e9ae953a4c7a7fb33c37e1ef652e810f17a6d7e767aef7850f1726c153faaf3c3761ff6c3b13020cbdc034f46fce0717a637e1852c3314bdc014e21b77ee05a637c1870f7371c849622738340a4e60c0602584c8082ec46ac0604580c0a48edd12244fbadd44da1224afae805374675c12253f06c6469b2c818af01d5c344612257f07730881a736be918ba900c01e83a49956a50580b60083a4d95e168129be918ba7a81ea1a8918b87a936034085a499d6be0011a1968b87a928be04a0a099d65e058353894965231a87830db5b8ce0e4a1843035558adce0eaa18458963231a8789534389331a878943650e15c30e4ab858ad0f444f3f9120fd300e550d4ab818a3ce8156dadbc7a03274e07c6e15a3bf0705c18688f39ce07a099b36d4c7a0527ac140d693da537a0208b6598cc09c7d89e95a16c8537ac21380a099c99c7d49ec96a2fbbbc88f60d0e25102b8de59bf3d4f4fa25db1de591f38a8dbc28f60f0fba2affb8260f0dba2c85e22cf59bf1d58b1a0bb68f0dbe2c28f594251bf1d38afde0a19e3273ca9364551d6db7dd8deeb30d95f5678e411429b0739253ca91643ea1c592aa91623e5275df670d8decb3bd109f9a71623452a3cbd8088520b67ad746bba8881462f06a910f0f851cd715231117032f051cdf158611a89462fa6a88b66ba4b2fa6088981115051cd71f238f06f9a21a608a98b460d30d071f258f15137b461a6a2d5955c3bc28341088fdeffc199115ac249e7412694bca2d5b54177ef2545ede58c4cf621c25f088fdee39bed45f6e58c2ce54f28e21b8fdec39f4136a257e48015e23f224541cba6860c22840410f66973336724e2ff8015a2375686a49a57062c5e3da4db0139c77b954397445d062cbe3a86b99b23c77bd54104861abdde98d20e130fdef00f5fb1263b1bbe26ef0f5fd1309e1ad398d20e1da61e16c476d51c8a790f3e1b5fb1c630ef169679d51c0a64de9f2bed86f0b65ff5cd1f23708fde9c4ade95fed0e7103f35d5153ffed0e7903ed09f6a8fde1c432d53755d41760cf4ac0b7bed16ecd1e22741f54c760c74bd5316fb07ecd1622deb2ab103d4d79e2dda13c5081516530b5515454b131516d3083431dad79eadc30a2df341802b5ce52d9adb893c8354227c20f38d2b5ce5214d9c3b3c8354c2699ae6bc2075a6d9aecf6d511ac40400a99a0104f969ad9300b26ba553b86f31bb0b6786dbe0ef27399b816fc01eba5860e8ab39332afcd7a376b3eddf86de57e4cc36ee324c66c9de5cf7b0884dc4cc4d5efed04d974dc4ac4801d468571329ccbb1d8c859914b5f8af71b6424724b1c87fa5ccfab26c36aa7658e3545f5cbe8e40", "4650ca390011cd3987fee8f99db8734aa0d0c8d22af62e01d22ea0d02a01f6c82e8110f62ae0c8d20120f6c8aad0d22e3906510a40d039cd9d7062973f908bb78147a88a44d3d4f004a286790c6f085a550b7bb23cf0a09cf2a0558bbc1c307ba05c0bb0bc157bf29c1530bb7c4bf2a022af79488c065a045a04af460ca279081334f44be3e2bdf5bd35f462e313f4cb990247e4cb7a5759645799c24bd93a475799c2fa4b19476459d93ac78b426457f5d3227423f4cbbd23ffa807e842b7f33d0cff81d5354416a6eb9f569e080be35a3c332c38733ff708a8c3fe73ee09743f773c33f81a336cf71a3333783c6c3fab88164bde1fe3a6e3a6c85f9eab160bf6e70d3a06f6543154f1273606f60dfaae32c0db0b8bb2e93213a5a1b9a9b96093a9a1b939a56032e92e0bc08bf29bb23136f60dc627fa54fa14f6274631f60d9765c227dad9e627e6a7e5191a57c2e7ffcb426556fd10bde590ff4b167dfd4210fd4b7d96ff42e5bd7ffd42d64be51027d759029ae5e7e6e7269725dae759c22be88197470581d2d5a6aa4540ff190d63c2a409c14060d49e3945d8a67325836054c200c1e3a449d4e3c0244182496099fda0bc105570430d55bf6ac0a6c5195a446b3224bb77608d74f236526c2d8380c48075fde8fdfcf5fd8044fdfce880fdbcc468fdc080f5fcc0e840bd84f5fd74ec762d5232838d834d6c3292f4762d76d35be4b686c5e0c56093c6f6f65ba404cd97bfbb893bb0bfbb048d3bb0c9973b308d89bbc497bfb084c9973b8dbf3be0b6c6db7653a4c5a4c576d3f6a0c65b1e420c52dbe04878df0372df60d3331f93a919eff7e30d94ef8d93e937d4a3190d94e9e3b79319ef94d3a3d9b729ef0d78de604c1b02d2481f5f13f2e043df33ff6597fcf95fb735005c0cd22d901aa5633c3f84434e8324440363bc83640e3f83647c8e03233f4424630ebf433c448335ff5fd7f9a57cb7a50050cc2d1c921a6389db8a876f5d415d4189af47a3db4ad540154797be9c59875cd54097997e159cd9807e5755158759957e55d700879c41a3af9b47c94a5d4a5d63894781afdb369ab56e3601e376e3361a4176b6b52eb9c12ec3f1846117fc53eae613be8d0565c8bc4c3d9c041f17f9c4eeb101836176368175369a2ee32e63365af63681b56c917fb6ddf1d7733445cbf02b1acad8b7fe96b80c50cbe2672e0bba90eabeabae2afabe108bab67e237d0968cbe78cb05da30ca6bcbd834d8345acb2bc530ca91d778a80b56b3aab3aa17968bd178682f23ef0221af8cf182cc2f23a1312fef8c31232fe12fef82f12f2f2f21e3828caa11d6b88b5768b368b391978b2ad678069e6cdf4de595ab952b5ee58d866cdfc5e106de74559c9eed36d2773f8fad6e36cfb76d3f926eed9e45d5c6f4215e9cab46a5ec0d5edf95df9506de8d6ba56c5d2b75b87fb6ced2ce526bb6ff1d75b8a2c35c46d053c0404640a243d0c0d35cc080c35350e25c4640e2d35c904346c0d25d36b57f6bb8ceb8ce5dabff523675820f1feedc0b4c6f4cafcfcb5c021f2e29c4375866287a816ec2df99f4fe6679c2fed9a6f45f796e8169e8772604187a6fc20bdf9c0f2e4c2e4c82cf5cef0b1ffe0ee6b8688c244a4a0891159cc080c115e13b8c8d3659024e7068e6e29093c4489e7481491dbb255e5d01bb89b425484a7e0ca6e8ceb824c18a00115c88d580bd0a0609404133ad33ad4a01803d064953517c23422d170f23175311024f6d7c174f512d02537c230f536d3c42512317ad7d0106800a493349b3bd0a006d010631469d1daa1a94709430861a6a719d1d41fa611e889e7e22340e07a71293ca460e13a78a12c746341387ca861267340e70b15a1d2a861d941d543106aab05a9d92d82d41339339fb7f0f0ac0f9dc2a46842700b52c90a7f44165e802adb4b78fa5f482376da88f41f4041080ac27b5a7fb12d36db3188139c1f512820d11e739705ebdb384a27e3b7e7b9ea20470bdb3c5851f4177d1e0b7c1a0c545f777911fe0f74551b7851fc1b745915ff705c1e03bb062bd449eb37eb33e709e44bb62bdce5ae97a0111a516bdd761a2acb7fbb08a547812f24f2d46526d8a1432c64f782d86d40f724a785246ca4f38b254522d9777a2bbece1b0bd238436b3bfacf0c8b1e2a31a60a0e3e4e3a46220e0f1a39a52178dde34434c115e0c52d77411038d4c5117c334128d5e111203cd74975e4ce471e023a0a29ae39ae3b122e064e0a3873f8350c4371ebd1ebdff778407831059ca9fda8beccb19ab2bb96e68c34c456b83ee4c287945ab1999ecdf4b8adacbbdc7374384bf101e93ce83823323b484aa83087237478ef70d1944448a82964d7c750c2f89ba0c582bc47f6c44afc801446fac48c4ff012b58bc7a0c4935af0cf72a8748b703728ee666ce080920ecd36dbfea3f57da0de1624d761ebce11fbe14c8bc2d2cf3aa39a51d260c357abd311d3a4c3d35a631a53914f33c2c88edaa8d61de1f7c36be62bea261367c4dde1fc55ad62df60fd8a3217e6abc2bfda1cfe87aa782ea99ec18bd39959a3f46e01e39865aa03fd51ebd18e859a7eaba82eca3c54f16f6da2dd8cf217daa2b7efca184d33439777806a9a616aa268a112a2cca439a40e61b57b83d5bb4556207a8af5b87156862b4af3db8ca5b5ae6830057a944f834b71379062ca6112a8a96262aafc89967dbbf0dbd005235dba2348809af47ed56736654f8b35d9fcd7941ea4c627617d64aa770df4f7236cf0cb7c1dfb1c0d003df803d742701640308f2d35a7c1d81b0c6a9beb8999bbcee61119b886c54ed4a99f565d992bdb96cdc6598cc52987703a8d1ae266af15f3b180b33296291ffe26c858e48885991fca19b2e9b", "20176f3be1c42e7f71e7940efdd1f33ba0739a730ca21480229a738ca094730002ec91a55d40a155c091a55d0221ec55a1a55d0240ec9155ec5d0240a191a55544f310b4085e8d18de10b408440df3180db408445ef39018a6a9e1038f5015893960f6e441ab16792bf6e441b916607996e441392b6076f9e04139ab16f66479856ee747fe510fd027e8977b6be8c5c6e8977beba745e846c57beb2768e897c6b2758ec8ae328597328ec8ae3285f59785c8aeb2b2758e17f5aeb232058ec897572d16c64d91bf3c1116c64dd73fad3c3fc64d57112d96bc6b882c7a18fe03abdc13e8105087fde73566d87eee7866f078d87eee356666f0e67eeeb57866587062ec1bf429ec4f8cec1bf4a9e24f6c0c4ff4a9626cec1b8ceca962eccf1b740c5373c164264a43734ac1642653437373e53765d35d1680171665d35d6580b717cfb384cf4d2e4bb4ae84cfcd4fcb3334cbcfcd4faeb30434b3cd4f2ecb844fb4fafa85ca21ff972cff85ca21fa97fa2c97ca217afffa85acfa217aff9785caac4d8b331aaa7ed580fe331aaa4d558b80aae08632fb4179210a02a557d0032f8fe74a063d738ab04dc74993c0a88401820493c0a8c781498281c0a8c784491382e9ed5a069bd86424d85a061be9e46da464061be9d8ed5aa476efc0b488d66448f9d101ebfb0189fa8101ebfb7989d1fa09ebfbf981d1817ad1fbf9018901ebfa418db7488beda6ededb7488bc1268deda6488bc16d8db7ed0d8bc1eda6b7c86d60932f7f77091a77892f7f77601a13771a7f776009932f77137760099a2f7f7787be673ebe26e4c1a6673ebe07e4bec104a491f0bcc19836c191f03c8418a4b6a84733de1b27d36f2733de1b28d3c76f53de1b28a747b36fc71b28275333deef3824354a01a0985b20354a01b818a45b4bf96e6bfebfaef3bf6e6bfecb2ef9f3c91c7e8806c67807467e8806c9f81c0778880649c61c7e879c0649c6787e0887025fb795bac6128f46b795ba82125f8f9295ba82465f378fdfba82c612b7150f33fd2a0eb9aa812eaa2a0e39b301fdae010e39b32afdaaae7d39b3aa812a8e2e6d026b5dc66cb4ec6c6b5dc66d3482ec345dc6ed6c02eb6c02c6ed6c346bdd6c7c1b0bf8a7d4cd2738093eca9079997a0306c32ef289dd6309c32e72835d86e38a6194b169b496573494b1698a96e15796b1690ab46194d7e3afe7d822ff6cbbd57d57cf5c1674211657cf5c55f47d217df196c56fa02d19a096c56ffd2d711955acf1d066232f17a3f1d066552f2c17afd0665523ac7117ac665523aff15017635ede05995f46425fde051963465ec2c60519e35f5e5e425e19e35f46de0542d74ad9be2b0dbc1b0dd9be2b57bcca1bbcbe2b578d4ad91bca2b570d3cd9be9b1e5bddda6da4ef7e24ddda6d9e6fdb7e43bc383d8baa8de9aa383d8bc30dbce9a56cea709dbb56ff3bea709da5d66cffd6709da5bb6c6aff6c9da5bb56ea70ff81a7b98c804487a0c4b98c800187a7a0878c8081c4a7b920a780814487b98ca0de173e5c98049fb9043e5c985e9f97b91f5c98de8417be391798de041f3edcb9fdcdf2dc84bf33e9bff2dc84fdb34de90830f402d3d0ef4c50f40253886fb0cc10ab0183150122b88101839510222b389d714994fc184cd1184994fc1dcc71d12127899de0d0ccc53a764b903ce90293694b90bcba0276136db2042ac277181bda020c92667b15007b0c92665a9502001592665afb020c0082665a7b150c12809edaf8462ea62204a6f8462e9ea25a04a2462e1ea6da78845a2e1ea6a2f8468461b53a3ba8620c54e23a3b28610c35d40c3b28e162b53a543528e1628c3a3b5426958d681c0e4e258e8d681c264e1525ce681c260e950d253dfd4482f4c33c1022ce7382eb25041bb9558cfe1e1480f3310273f625a6db662673f625b15b8266696f1f83cad0055a501f834ae9056fda4f6a4fe909200059204fe9094f006a5976c57a677de03c89e07a67fdf63c45093c67fd7660c57a8945fd76e0bc7a6709ef223f82418b8bee0b3f82c1ef8ba26e0b82c16f8b22bfeea2c16f8b0b3f82ee59e19147086d667f6ff7617bafc34459c3617b2fef4477d9224a2d9cb5d2f5028c9ff0a4da14296494f0a45a0ca91fe4a9a45a8c949f70649f5a8c14a9f024e4c9c04735c76345c0e34735c749c540c04535c7c9e3c0474040c7c963c54735c022061abd18a4aee9241abd98a22e86692ebd982224069ae9869822a42e1abd69466809279d0705670f06213c7affef087f213c7a8f6f86086f3c7a0f7f06a18886998a565772ddd0f28a56d706dd995014b5973332d9bf97d99733b2943fb51740d8a7cdcd9c1112052d9b1a3288881407e41cef550e916e8e1cef550711e46e5e91035688ffd888ff035688de5891886a5e19b078f518927519b0f8ea185e129abc3f7c45c36cf8c33f7cc59aec3c786c7cc51ac3bc3ff8b41bc2db7ed57faef47a634a3b4c186a4c634a3b74987a6a10db557328e67958e655732890795b58fcf8439f43fa5457fa439f43fcd47857b55bb0478b9f2cec1fb0478bb5ac5bec8cc03d7a732a357faa3d7a730cb5407f7505d931d0b34ed533d931d0f54e05d52d4d54584c2354142354584c2d544d1427f20c5289f0696ef00c5209a76972ee0e505f7bb668abc4685f7bb60e2bd0c40701ae7095b7b4cc37ae7095873481cce4a7b54e02c8061069101300a46ab645017be86281a107be7f1b7a5f9133cfb682d49966bb3e9bf34ee1bec5ec2eac956e83bf9fe46c9e19cca8f05f8fdaade6375d3611b322f943223611333779ddc30a1d91c422ffc5d9537d71f93a02618dcb3099257b73d9b8a35d4da430ef0650166652d4e2bf7630ebcbb2d9a8da9532"]], [13, ["75fb01b87bd90b269fdd8b3ba474eb8e8b9febdd743b8ea4eb8b8e9f3bdda47497409ae7d5e969da9a976940e9e7dad5699ada97e740d5e9da69d59a4097e9e7674ae1345a451411e167144a4534115a7da1f880ee9f33dff87d33a19f80dfee73c459f1d91cb0085973b0c41cf108d9b0590873f1c4d91c08b0d959c4731cf18bb3385715da9b5d5f9fd1f6ee460768d15f079f46f668ee870e862c32c61f9f78ad9d9a8a8d2d0993fe019f4b8596f25bd682ef64f8e601825be6d6f8ef01646cdba690811316e228f32d06b7e475c12d2875f3e406c1b7752dc12806f3b7e492426cbed85d70536c9270425dbe53d8706c5392be42d85d5370d86c42925dbe5f764a7c947c40784a5f40767c7c7894404a785f7c76947c7840944a765f7c7c28357dfda42597fd7d28973525fdfda4977dfd28fd35a425fd97a47d352825fdd16c4ca395daa3993445e326a2fce5e3e334e545fc26e3a2e5e3e3342645a2fcb6da5074cbf8f5a450b6f5daf874a4cb622d599e89ef6fdd59626f2def9edd897d2b50b5a9081b38507d1b2b08b538a900686800ae00a1bd6800a1680000bdae1271e39f4d59e37aa96e770d19e7301277a9306ee70d1219aefefdc6d0377b883e52ada7b6a39f80ad3e9f52a3a780b69fad803ea752b6a3809fb6ad523ea3a701c9aea61819275cae0127c919a65c1827ae5c01a6c918195c2718aec90119a6408a9f60cc31d9eb46ab9f21ae41458d9f4645ab41218dae459f8d4621abae4174445ec028750b9f5e740b4475c09f28d2b5d9df5f658634d9d286b565df345f9a08a935de8d3d3ca99a3d088d353cde3da93c9a3508de8d62fdf6dc0305d34126d633c0cd209ee8ced042d52513a9eb06bb694f3b075efc69065ebb074ffc3bd3bca10d8c2bd7387292f16a18cdf5acfcfede45f5183ee9defc3efe1845e9f5590b045831ef5b118ec63bc7de81fa773b8efac681c777defa3b778ec7c6de81edade930a205105be9ed10ad05305ba210e95bed30ada2055b10a2e9aded05305efe11e6d50774d6115e74fe07e6d6d57411d65ee6fed507d674d511fe5e07e6472bcf13d745a6cbcf47a62b4513cbd7a6cfcb47132bd745cba6d7cf2b4745131473890f1c9c1a0b89141a739c0f0b1c1a890b140f731c9c0b1a1c8973149c0f1e1ecd65c788f7d5cd1ef71e8865d5c7f7cdd51e651ec788d5f7c7cd1e1e88659404e3fba651822fe394820451fb2fa682e32f94fb04a65189a9e3f0cf43f734b9d0923c4e6dcd4692b9cdd06d3c464ecd9246b93cd04e6d46cd4e92d0b96d3c90442b44bf0b40b92b9040440b44b9bf402bb9904444bf0bb940bf2b44900b441a5d6fd3ff4a95516f1a955d4ad351ff956f511ad35dff4a5195ff6f5d1a4ad3a99848e8cf281d7d48a91d9828e87dcf1d487da9e898cf287d1dcf4898a928e87d663b1842894c6c3b7d4c6689186c424c3b6c7d186642896c4c423b667d89185f4c0d31d3220acd0d5f0a4c2231cdd30a0dcd5f314cd322cd0ad30d4c5f22312d35d13905e836ffe4fc0f30000f00e10fe400fc0f30e100000fe1e430fc000f8238be65251f7171be8271381f6571253db340514732e812403de8b332511247511d2a734b181b0e2a511b1d18730e4b1b2a0e51731d4b180e1b4b2a1d511873d71df0249cc5f631f0d817f9f5d8319317f031d8d8f993f5311793f0f9d8f5d803e8d983b3c81309d90313e8c88309b313d9090383e8b3c80913b3d9e803c8839f6f3d3ecd2a4b3a3d9f4b6f2a3e3acdafc135af3e60cdcb35afcdc160afcb3e27f45def7336f91a5d27f9f436ef1a73f95d1a27eff473361af9735df42736eff78a32dbe524983732f7988a24db37e5983237f7db8ae5243798e5328af724db6b4694bbf52f5212946b52462fbb12f55294126bbb46f52f1252f594466b2fbb4e6025a13f580e6e254e0e6058a16e3f0e256e4ea1603f586e0e3f25604e58a1b1de9959500655ed99b155de0659ed505599edb159de5006ed555099deb10659c5b7ac51de47fe50acc5feb7475150defeac50c551b7de4750fedeacb7c547513f29611d075b4773613f47295b1d73074761733f1d29075b73470761293f5b1d8f06b4b9eccb2474b48f2406cbb974ec24b4748fb906eccb7424ecb4068fcbb909218591278ee71a8509e7218e911a27e7851a099121278e1ae7278521098e91166aa80fb66dbf6ca816bf6a6d0f6cb6bfa86c160f6ab66d6cbfb6a86a166d0f92fbe06592fa0adce0920afbfa65dc920ae0dc9265fb92fadc0a92e0fb92fa65ec814289a3539b7c42ec9b8153897ca3fe9eeee6695d313684933ef2eb599e052aaa09b3207dd8b7092ad8aa7db3b720d809b72ab3aa207db7d82009aa2a7db306f04b2a445f534c6c8372f9d1bb5a2ec4d3f2efadf64467891d4ff56932ec96d59458f84cbccd8e58d5cd94bcf88e4c11caeb2e6a6e90b6cc9f77d0eb27514b888a95c55a05631d9588638a05c51d5a63951d88c58a5a051d635a958a8805c55e4780bba2d05557805e5547d0bb57a25580575ebb47a2d05755a280475ed0bbef2bc4a1cd07b895c4efb82b07a195cdb8c495efa12bcd0795b8cdc42bef07a165db785994367bcbc01ea2d010c6161fa2c0161ec6d01f1016a21fc0d01e10c619c977ad1b09fb84518626423209f0f0120bb59218a39726ec6127cfbf632ec1b6bfbb9b3c15f61062aafe0fccc2d44fa93c6fed60df1899b051650f7e7219bf9155069f95533ced0db7a388d8a449e100859113ed69e15dc065eefb1b0ae27ca4ba76fd6df177aee0562c6c7312ca958f6812f25b8d95f63ee3e67a476779334462abac121b9c8e7eadf5b8813be752f2e1a15b5356d58fa653402cee9f1abc", "a55b77fcec5edc21e926a55b5f74fcdccb5e30a9db0fc0dd3fd7aed6bc4c034aba4c3fd74eabd6044e4fd3be04d23cafdb71245dfc5cefa607aa4e4fd3d4be3ca289d00a3fa3502a04fc76c7ef9b09fd2aa28838530aa7d18847c8ce9a8325e69ee3884780cdce22e680459823ce8acfff9cf9ee0bc5077427cee680cd42988b373a40fbfa8cb67731fef83c74306491d0deec5a9cc5b9aa2ab4949ff40ff85c7f0f2013dc32b7c66c6c49c06bedd454b247738ffe3af834c3370fd8b2167c2725af0b46996f31b898bf25af6b0946319cb01067db36850cf29dc266938413ea92ecf29d82c36613ee829b921462f3c53708be6d41a99b2715c2ee82639b92f4e3c3a354fa02b2e3fbe2e3c303a254b2e403c2fbb253e2a3e9ef27ed43b9ac294129e9efbf24edab2db9ec47a9e9eb27b3a3e40352c2fbe2af212db9eceb47e9e52f1fa7291a37112912e52f1f1fa731d41ecd8c66631aada7235d86b2add7c6f7ec4ecc127b6b79c6af27b5d586a25b3719171da7292fe27c7feb166bc9f24ca8c54985eadb584100e875450308450345d8c0e95b81aa4d3887914875bb6bc8bed94374f5ef3786ca1ad793881bff6c0508ed05404303706f90c8b84b85713b3d05b46df5f9941af2193d05fcb46d951dfd04f4916a3db530e5c2700d3849ce0ec830e53ac1704dc838e10a487635c595b21dfd6c05f4394dc6c83871e50a300d2a6a345afd0c7159750d2afa6c340a8ec95e0752fc046303fe44f1a25b20aafba6f9ca9636ac2da95bf8a423f202460a6974fd342a5a0d2a33a491aecdfefeace1f14ed5ec416828980e12ebb7e71e6eece1d14448adf199485d778616aa2e78e2df4933f0da3d06f14437b19e016e41f06eec49e5d1ac39f0e237d84d7bda68ae6795938c57c3284aaff7e6f7f1c75cb9c699e60d6d600ed4bf7334de39f636f60ed4dfb9733c79df8ac85a20c08ac7f049e7f7f72eaa3cbef3de71d4370e80d9124d6f87682d6d2f80d982104d6f2d80d86a6f4d871130b7ae8ef0a2f33ff73a30b7a6ab8ef03ea0b3f6f28f30af69152d8048df6a87f7af3ea08bb0f6329a58be7e3e325d29392a9a5836bd7e5e2e325d3e5a799eb87c58e048a4d098e3a3e07c58d0e0489ce0d458a0984b7ce058b92e327d5e3e9a98e3e0d4485ca0782cab3e6ef6b8f740f0402cabbe3f6ef646bcaff6f0682e3bda7f311da71424881ebaa7494c1d877f8d127ca12418df37f33846bc6faef62827308d121c7fa1dce3317292cc6d866ece6de3316a7692846a6b36ca8596e47120cafd5d8104225a825c20ca05fa5d215d00ca85245a21fa81766a6b9634cae522fa5d005ac985249a8efa7fd3a8ec52d2509a8eaafc7feb57aa8cd2e87a9bfe41ef7b464aedc0444c4541efeb7846c246e9e84bc544427feefa57aa7c8bd298c77c46e940ea4b45c46013dae963324beb4bc4606312da314a6462eb33dbc11089699e6ef8526012fa12896956986e60165168fe626a889930134a64da61ebc3619a16516868fe8a78000827e77f8001e10778007808278740b7f96fa989ce29288b2bf1158cc3f989923802ea419f95f9888b13c4f12d2b800907782007e07f924197e899058a3a9873585289dae8c088c29873d85852e9c2d87088ea50995bc78e9984c7bec8afc7aec78eb99884cf2cb68fb9ee8027e1eb58c2d85071889ace9facbf808fc1c61e4c98cd1e9840471f401e4c9898cd46459e481840cf1e9cf1d169eef95c7a537b5df6a9796d0e065659d2f97cebf169449f459ec84e1818016b5e7e0dae79f579d798eb3ac9a7b73fb179d7c89feba2b3c9d738a1ef7a9fd9be2997b9c75424bc27d9bec12c975127c1bcb95794d92ea79fb3c9efd23879562c27c194b9b9dfd995a8a75c93327a5a7bd99590aaa7347f91925833a2dcad0a75fb29717200c373c20a7573f82901c1727073022b09fd35aa7f91a29458db05fbc1722871730ac86a87ca8cadf2368e35c86aaf82caf432a86a8ff5cecc828a82f2662df6bf3d2d3e8a82f2f766bd3ef2872abe658df2f28632a8ca6c8fcdbaf53ef267852a8eea983b08fb394ad9f9d9ea983b3a084bd83a9afb4909eb38cea563a77d243158785ccea52361a7355f26a17b34a0cd654839d83a0a9bfbe935605f26a1a57bcc8cd438294c380f7149708cd4383f290c713cd74808298c3c7b60b345b5f8556bb3687b60fbb545556dfb65b350437db00c39713c2fd4488850b36dfb4565b3782fe396049754d8d797d42fe3569004dfd457e096dc072f934ae41b1562df0c9ccff22c209cf4915f9ddae4630f144a1cdb97d45700e7962ceb8ab1f1f774374f9bbd054950c156ed55e99bbdc5064950e9c3be55514d9805ded572611b94cb8f9361b74cec78aa4ffa9a6232805f52215505e9c34eb85599b5273a239e967f6fc57764c2aa6ea6e43f895a62febc835ee26d76aca6c4c26728eed0aa441c532c442c28ee18d3aa542a18eb4054ac2cd67383b48d505e775156d42a18abec402cdebd1205f4aa3a82f282debdaa12053c85aebaf23a02dc1508ad6c267ec75d39793f08adc46d265e3ec0ad7c5f210e6d3d1285ae02bcf2da5d693ec025ae7c0f30b6f800f6108586f68030b610fd0086b4d95b2edbc6cba24980878f323411921d7309660f3b79fe48d827cc48be6bdd86fe801005b6f03018bd349158a895c416a67e1253f57f6093cbf8858d2a7bf0a9b087b0fddddde4264d0a6fb81d45c45010e7032e73dfdf9ce2698fac32f8acfbc6c84ce5796b074f0bef02288c9c689350ae04b762619b3acb9bf11937d73b8bbf7325d5b5eb6fdc3997f26badc70dffd4e0359d026271d8e07424125b65956aacb47f449390dfb2aa7e940f0fdd9a", "a2e3e74e3729ddfa651a50fab976b5e6f7e20e29ddbae36790e679757a9af625a6f6e53950757a9a5ab526d065fab9767e00ee5ef68249dde77a37dd8e23e9e2df4ce827e0b73b7e1c2c31473c4276d6198552114d8456f871567c36072cc21c16c25c3c7136076c6c7616f11c473c0252388d561145c499283ea0fbe7cc775f83218b8cf1c7e7a17fc0e752a1a5fca467b4bdbbd101dad76ba7a662634b025eb5e03b19be79c09696b935fe7b0099e02cce5585f666d7e2d7c1a7913d9a7bf44b308ac1fc2d795d249c5097ef14369b7c8bc12d795d30ca109b2f7617dc94a4db94a4af1076171c1c369b906497ef14b62964e0848538db4add3cb941f06d0b10a592dd171f1f1eca654d497f3f691f17901d1f1f1ea5d24d5f3f69c9653f4a5f3f4a7f0d69c96525695f0d4a497fff9d121f251f10de9712de179f1d251f90f8388d4991287ff96dbd363e1de93294d1b889287ff9384d3614dd327e3da9ad4b9667e2fb5bb758d85bcbbb677762961bd368a5f66866344d7911bfc9b8e83840281a0040af2b1adb5d43c6398c44aadfc60a422d4e2a54dcf86753d6b89e442a8cdb798344c65d7fbf31f4cd1ea2ab0a546d2ac2064edf1a1a802b40682f00a76dab94cfe829e0c04972862917866bcfa7d4e829a06dabb2ab2946c60957402b5780693246c68909866b72408629d754eba9ede827a08f2ba0cfa994ede86767a351c8aa6b50d1dd02511df0278a17ea67886b5051a3d19117304addc2271d6df6f75799218d74b4616dd937cd57b6e22718734cf63a9051d16a5048a3eba7bf3df740c1749058b45075c944eaba33660f42630d8f77aaf50c70338827ba896edad3ce8117bfc181d7eec113ff4e9a426a8d77630f8f262a8f660d8277634fbf8f3f46517abd37f1ceb177a0fe9da364bc1a46733dab9c020156ccfb5644d6a3be71e0f19df78ece9de3b1b177a0fe6f6803e3ca35ce34bf77513d864f3abf84687a6b7b01cc16179dff81b97575843b446b01cc96687a7f8479f5019db59784b597b97ff5015d5d7584bfd781b9356b3a8c6801c4567bfa563b4cab680144e9f5f3ca51d1c4b285c61ce7c302472291e94ad1c4f2f5f35ce20307a7c602c5e202c5c31c07a7460647e21c05e7c382caf3c47591e9f2d1f3f2d1c4ca7591e9fd71b387076259f5a52041d4fe8be938c7bd076259f571b3c1f8be6994e00b25f80be53e816994e0ea38fcf3d03d4d624773d931e27db58773b54799c731e27db39324746e1b8f512410d10251eeef0a6e33741b8f919364d10ad1ef02502e244a2e2411d1ef02d0d0ef0a11e402512eb4248f535bb3512ea4512e0fb4535bb3e5ff5b9786d274546a07260a7adf3352466597d274d4ff9b2612fa334a475f2a525f2a3ae6334a07c73312662a0a7a5fd7dbf4bf526594465b94c674d7bf52e593d08e595f22061b970293484cf374c31f935922069bd04e5343ccb48842f31743f3570cd3b48842c27403d397484cb3d90e865022135b9f0e5b1f86995022d34338390c3fc003c0601cce47595c89afff030cc0034038398e6f59c9475c9c202c50d4910cba44cf0ffaac4c94c411504d744e01bacd7f4b3900ff034c38c003c6924a4714c69cc3f6457e3d76cc243cd44607c69cc3924a073c0967b17dcc757c0c3676fe64fd05c5247c3e763d76cc87cadc12c68643548a43d45cc712c686c46c36fa00f260c2e7d29b8a8f4e73cfc0043af260c26cf65b8f4fb3ca92cee770cdab0f58f3f26b6b7330d8ebb24fcd7af6e02cf244c20076c2c020fa2cf244fe5c17fd89cdbb463da622c9f64db9cc493ebdcdbbc65cd7a2cc763909e6cdbdcccdfdb6623909a666b98ce23dc9f60d7dd7fb9c4dbec60997c6c93bfd9c4d7e543da5d1dacbae8493031856a8db4f899a94d1cbae443de55849e80f96839b13899b5328d80f9643c34f09981356a89b11e56efd8b94c49aa5c4daae51fd8b141554a677ac41567bb1ffed511494376b6c95b741563b54662d6b94f7913f54f12b5471d4adf7913fbf37eb6df15114947766169441557bac667b6c9637944155d14158cacf56c7dc2389c1722e1d3bedcf51ca56c7dc41d8016d2efb3209dda32ddd63ae01fb3209093badc1e3722e1d4a58c7c1d6d1dc4fd8dc4f47cac1d651f94961488263a4c6c5af5adb039b2daac2798863a4c649611aea836ddb2f9b852a9bc5839a6ddb2faf2daa9a45db03db4861e489e3b94642a1464264c889e3798224f8bea47e19b7fb66e05422dfa810a4c2be7e19b724b8a050e2e8d4261f7ba7bb795a578c8dbfa48ffc7a966701e13e7899a4be02b7e438b764d9bea4be02364882aa4adfec2da05c7ef4ae960bdb0ab66adfec2d4882fc920ad1d7149301b4fc7bab3dd119f1c7537d9a0cbb65626ac22c481ff6ad8ac2adcaac2a481f76e71df4fa49d412f3e2986241718756257533252fbe2313566265b156c15807a2650762b1a256c1589856a522624171c725163e136fb36335f2ba8b9a1ba46d849528e09117f4ee553beeca41686533f157d511f4ee9528a00a7168f3016ee5fb71e57be84af3012e6e33f1cafb41682511e0ae2874d595d7e095d7ee91287415e80730b40784b185a189904c023c7c9487283484b1c507b0f25deb46c23e614642ad24c6e8a589c4d8c9f3ef984b307b365e16a5cdde72d9b0858731f407842854d9839f5cc62f6ced282236695278c3aaff03b330f5939895c167e5144f7b6461e4447b5a78174099fbfe8682381f70efee264f853d84edcf5b3bd83746662ab8b9ded159de8ccf6b3d6ee0ceb9945f150bdb9c847225b8d82aabc406a7239178e8d69455f5a37c14108bfba706afe9ae5d7f5bfc9d2ba99a84fc5663a5fd23", "b5ab352fd380d2cfd3b42f8134cfabd349e9d6171d3f77bad3cfb5d3aa35812e1c49173fd7bbe976aad3d334b52fcf81d61d3fbb177748e9174ceaf60370f7b211b2b3e6608939e26011e688b3e2b339bfddf1fb66423f0138e21160b3b388e767befb42f101dd3fb33960b310e6e28922b4c2cf28948a682822ce94c269b48a2de527fd033e970a5b12f05a3b35151b3f3e0f1d0c59648c03c804b7ccadf1dfd1dca3bf0e3e8deccd03b6ac05dfc9f00ed0be3ea3eddd8d37bb166771ae2ab4a7b0d924e184ba7ce0a62485d87cb1bb6fc9eb5a82510ce6bb7ca7e0b0d98424826f5b50eae6c90db0bbe0d8a6247d85eb8251e65b0c6ec92cc4d9b64d210327fb49fb502e6b4afa2efb516afafa494bf8f8f0802895ecbe4afafb2f49fb6a5028f98094f0bef8ec484b2efbfa51fa6bf02895be80ecf8f880f0beec94f828f94897a16cebb5f1e9eb496db5a1e896f144f9cbc7c7694c8abb13b3c4de5ade3dc645c769ca8bf84ddfbac55ab23c13dfcbc7698ac64d44f94733a3d998462bb5612452ddee1a32cec6f524e2c63f9bb27a5dd10042d10000f6105dfdfb8da16f427b01d0d0005c012432ee5261dcce1b7152a1fa3656106a3670fa56a06a5311b9305c034e92334c4eb802925d4d3132464f013f6d5ba57c324cb94e305c93036c473f5b017d4ea531324e5cb9024c93016d5b7d3ea5464f3f017da45a4f6d473f51bce81688ea80163ee988bc8051ea5d838a3e1b8d425669beb2a50d6bcbbe1a5d3f8d8a5683420c69a46bb3bfbfca8a1a8d563f435c83b2d781143fc1986352d79da185aa4b263cd14dac67809b41a683c4faedb9070af877d20cbc760f9ebc1b7b5279346b10bcf80d76d39e760e78bc53357b101a6b7b783411526bbc1bf5ef1c8d778ebd03b722b21608b062ded2ebbdf97dfc318abd03f577ee1c8f8d7cd2f9fdbd8bea31efbc771cf58d038feb59e524e3d5309aae71a679431b1857adab23bce8fc0fcce8acbdfc23ccab0f0b60b62044d35bdb0eccade9aa23fcbd450b20d2b7da615aab0fe822acbdccfdb644d3db215a0b6020b6da5bd361440b1638122934e6381f351628e6121f38388a26964daf9f578e381f16343812e728ae8b4c9f978f26563838351217281ee696af9f8f4c578a264c978f569e27ae8b5f4cc7290509a2f6045f2809c6f74da310cbaaef8f9b3d3cee691253c7e19f878e11ef9bab3dca3c4ca304c75f28f709aa8f9b3dee3d10cbefab3d3c9acb8e11727f5720818816888072218956887e17db788c9a9d24a173178872817e5788209dda9a258d7279a07e178056722189888c9c24739ba1db789a8d72a125799cdafb9e91523b3051d03afa523191d09f5194a6a32affdfba3451d0fb3a9e913053fe952adfa234a6bb9f513a90fa52d131a3fedf342abb94a62aa334badea6ff959aa71bbe14984462149abf981a62a6451231d8988476ccfa44629a15a61b98be84129976d8fa30cca645141a9abf6298d88476fa98cc123199d8facc76308412e24a7c05e3703ecae2e204717ccb4a3e011e001ec2c961f8248e807ad06765a2c2011ec801f81f60d0257a6681a28e6400c2c9f91f60001e6dfe5b6aa2730ad06326e1b12ff2ebb1ed63ae3be049388b30e61c3696543aa2ebb1632e26e1f3b1963036541ca2e63a27eb2fe063b0b1f31c9654a2363a30e6361ca23a54e69630749a7b3e97de547c96743edf7a7c9a559007132666b3d107977d6a5e9b83c15e679127b2130606d19a975f836b5e7dc01366b30726d09107271206d0b30767916fca65ee311549b6306fee1565b6cb496cde35f2e7bae84f49b66f30cb6514efe76cf2bb344edee9cb4930656eeeb71535e6ba4ef2e96ddef2354ee8bbdee76cdd7e4a9c1cc0b0421cdc9cc04a427fb05e7625a4ea298dd6b042dd1c7e4ac09cea5fa42825d6768d7eb01c4adc9c42c125ea29d7a48c5e76a424d68c2877eb5fa0bc598bfd6f8fa2fca18a6f59a3bc8f0db2daaba032bd638fa2a0fcbd596f8ba10caa32db63b3bcbd8ffc59a18aa36edaa13263abbc0db2aada63bd33b3a00ce9d8691f490c967349e81e0d6873d997b63ae68e0ec2527e9773e948d8690d1e0eb68ec2e67e3a52d8974968e91e730de60ec27e8e52b63a8ee67e52c23a0eb6d86c512d7ed5da1e7ed92cd4501f6cdb1c2335ce4f0a4312da1ed87e6d51d52c4e1ccf0b351222436cdb7e51d92c1ed4354e0a13ce431c23cf3512420a234f1cf94685d83703a71236f9d803851247a7f5cbb81524c1f7253c0b08277de4d7b325f515c0b925cbf6626cfc3dddcdd3bab825c12515f6f5cb15b825f7c1cb24f5b55cd806e5f2a377a6980ce0975488befa666fb141125455d82d133b9eead36441fab0136e55665589ce88a7e5df5bed6f411254b055fb66b06f5554136641fa3bb42a11c7140b8ac63a10152b8bb50aa296983fefa0d74f0b8a3bc6b42a1511206d2394d75dd4dcb50ac62a3b108b151d99b0aa9b2979f19b1dab29b1f099782b9b89df71570e42702bdf5788439b0fa077afaa44018fbc0f422b719b8957de44a1ab00afbc768f9a0f70892bdf4357af4401bdaa8ea077abaebc8e007745a1e0e1a30c4d846412f6093392ef5a3712208c2d443f80a13d5c82d9c34e9e7fc73f2044812d3c8ca12f4d24166a2531462d3e803d44a1218cf696cbb6f1b2286d93c21b6e4711b14978da23ab0c3e2ba7327e61a3ca1efce4c4f980cbdcf7371431325379dedac1bec2bb000a2327dad3a99fc454fd1f9885ec216c7f7737792acea5fc5aeb710377381d89c456592536f2667cc6cdf58ece35784da78058dc3f2bed1fd124e4b71aaa1fe5c343b7a6ac942bc1ad58d8e624ef5c4975edfadbe2", "795e9d9ea67d09a4ad0974997eae9d5606947eae5dad79997d790e549d9ea6a980bb97bd6052b71fde4db7e348baf8b9f8b9d34d4ab7bee8b8434ab7eef8d9bd159fcd018b30479c9d453cc7118f009b4bcc118f909d350730174f9ccd019b854ea355441171a6140fe8fe39f3dd178a13fa09f8ed8edf37a1544413a1157e46a9a9d8d89280d7da6e8dff1e4026b865f0b95468293fe91ff84e866f1eb0652d7355a1bdd9b5388bf069648fe61efd75c82263fcf179e8606def6e7480f6f519e68bdd05372529c4cd2624d9e53b058727d4e53b85cd260925e92b84dd05c7360a19386121ceb66d374f6e107cdb82528c62307f4b5ed71262704b5e178c32dfd74f5a72d98f52d3da578352d2df7f495953d2df4fda87728fd25f435a72d9d7c447c90784f765a7f7c56747c907a484a964f7c5c787074464c7c78747a9f40545b78c5f4f6aab0dd6f2eed99d9825f6af8d4f47ba0c655be599f8fed62dd692345aa93d9a19cdc65ec46f322e3a4e534e635224ca5f3e3e6e22ca5f3e4e5334fed99435ae2711376f0c7db387e8eadfd790710e2391ea76e376de209171970a559b8ab081d3b70206e00a10da0b80868a0600d0eb8a0610b182508b930ad5b76a8a9171c21590ece19a1c9061ca7582929c61ca85e11a7015609a8c9171e2ca7a6a3bfa09e823d5e8732a653bfad90adb2ae5337a0af86929357a0a68dbeaf3058c52b7f04947e4585bf64df3952d6d405407fc89e245b7fdfd556648235d9b09c61c93bd0ea4f8b41a14d2e8fa69546814b2ea1a54f4d919e21a54d468b4fa03dc0ce2896e623db57bf0c4bf9366e0545d3291baee0c2df6b473e0c56fb09b5ae3ddd8c3a38990a35983e0ddd893cacf3d50301d24d66f83d058c3e39daad98015f3be1591b540e7786cec1da8bf7373ec1da87fe768bc6f1c787ce7bde3a8dac0b8728d33cd1b5d548fe193ceefefe38f51945eefcdefaf86d15ccf2a2719615e7d4067ede51f1de1ef75606e4d57e77f606e5d1de145ed65ee5f7d4017610e235a00b1d5de9ad50ed32a5a0091be9adeda5e00b30521d15a00b3259ade0ef8c0c1a9b1403197913847c1f9b0a0c131c7f9b0c09148a140f130c7c1a991b83c715d64ba7cb4f27c34b1725d64fabcfdbc725434b16c7aba5234b17cfd7c64be6f1a25f84249300eff3c744f93983a4810b5ff623a4e2942b94f601a2538fe5c768c785fede1d1ed51e6718c78df5cdcece18158567d7fef8158567ddcec7142f4bb00940b49b4bb4204b940940bf444b44094fbbb02090b4944f4bb00b492c9e3d4d66c940b2d94cb03edd4d62c6924099ddbc663d4ec0cddc663e42499db84fe8cd2d1978a898c84998a82ded7f1818982def78c94da978a8ef98cd281d436fdaf5419a5d1f5a531ddf5af54f916ffd6a5a1341d55f9d9a5341df5ffa65110332da2d0fcc5d4ddc0f42512d3ac30c02412d33cddf0a5fc15c3342da2d0d0832194c8c4d667b6d687612694c8b4c3b463d69788c1c624649688c126b4d3c75b56f211172788e33e2b13257104d48387f3511657e22b18147524832ed1330b9d53806ef3df5213c0ff00130ef0400e4e0ec30ff000f0100003f000104eceff4fc2596c1f73dd01099f8f5d8f1d7331915f8f1d33098f7d838d9d3f597f011f32b784b1e110d5a11035d7b184b1a1e2a4d2118531e7b0b1d18131e7b0a412b5e3d3acb2a4f3f9d61c0cf6baec53f3daf4a6e2a3d3dcf3b9f3ea03d6bcfc1a5c3d388b3c9130809e3030883e8b3c919d9b8d3e803c983031818e3c98309b3d30b35d4e827973af282ea3784fb27d8359a948b27d532e738f73bfad584e822973f53e6793af7142df71f24e3f6793dfa5d7457f62f3ae913f4f6ff3ae31d7759212fa83e5e0e604565302e68415eae6f0008615eaf653e2e4e6140af683e550e2b95bff2225b16644b1b66b54ff2245294f69b4f6b22b215565f4b22b514fb9261ae57de40f557ccbcd7a5b7c1405e5ef7f7b1405e5cd5aec551c75eb7de4cf0a99056550d51eeb9d1e9be50d655095d995e91d6b90d55e05e56d90d50e95195b9bcbbe4c42f768404e6bf0b89c4b47c262b09c4bc74efb48f7986bc0be4c424bd671b07534f79312f7d39172b07514361096f2b3d531777494b2d5317710f673fa60dbf6cb66a1868baa66d1f6c0f66babd6f6c0668b6af166f1a066dbf68bca1879e278ae91105291101972e2785ea8521892e018a9717e1ee218a97152987094383ab5c9c71e2823bf9ee5594038e9193895c8372ac4be6e9ed61563e3efe95e26a9afc02db90f2d59b62fa9af00ce09be2fa95fc6ad20b0af5fc62d092ea9a442f435c56400bf549f26c36e99d8f1971fbdabe5c23628ffde6a4f74463c2d300bd2877daba29aab32ab0ad2879d7092a0aad2377b8b0dadda377b0b92a08259ac5530d681a85855a9885850dc31a6a65850dca15589388158aca8553056d985cfc4dbec584d89eea2e606691ba1bc07bd7e12b5c4fc794cc98befc88455dd1cda7c805bf9be424cbcf27e105a89dbbb72105ad94cfc8ef91ebad27c804b5cb82b0a5d75e57504e5b57b240a5d05780a78e405bd7b55257504bd7b250ae855d7ba91b04f98917cf2fc3be612cc1e76222493000f1f65682b89317a6922b150974569b3b75cb68de1610cfd01210a6c010ced01616c21fa0a0d616cf101ec21f05939c5d31e5965bebfa120ce075ce68a884d9a14de703b39d19e16de055018bbc953610f61fbbbd60ef68d9199caf3f6e02797f10b1b55ffc02c4cfd24a6eaca2ab1c1e94824b6c4e2fea9c16b3a058f1bb8732ee5d75aba356555fd281f1ed7df167fe74aaa6b21bfd55869ff8826ae77749637e3336ec23627a15c096ec5", "73edb46a4da0cbf4f4344dedcb73a0eaed4b20cdf3eaf434d2c5cff56eba1d47c7cfeec51d52ba7593bafd00dcbdec056acdcb34a0f473edbaf545c7cf9d6e527804d8ec2ce2398e0ed82c84b978e26c8439e2acf86c0e58efbe507c40f7cf99adf0330aa5229a088833a5701aad228aecac3958628e788477fcbe99d04fc06f32c12d736bfcf700802d6bc177327cf304bcd64e4dc5c696f7e8af834f237b34b4afcf687b77a303aec5599cab0aedcdf949ff80cfa5424bcf4307431619e38fdf29386c3621c92e2e38b629495f21ec294921365fec2eb8db1694ba797283e06094f916835bf2ba71b66d53c8c0090b6c364938a12edf29f2ba96601483f95bfefe4bd2be1a949292cbbe7e94fe1ad27e949abe7ed292cb3e2025bc2f3e3b4a4aa52f203b3e3e3cbc2f3b253e4a3e20d23e94cb9a92fe7e3e3c204a25bb2f3ec42cb1b79677cfee6eb1962ccfc4f7b7525b6d28ba65fc7ad1719af2227e9371719aa2711351fef2cc6836a6d14aedd16528db7a6d7c3ad2fef2f1711a9322514457ff7e63e89b3d8cbb5418b7f306893d89b8f1cfa6ac715e003434005780d054a8be8d15845a9c9cbe15a8da54840d8954b7bb868c7318573480503400805e53ae130cd7e4800c8c1357ae00d3648cae806457538c8c13d1cf56409f5329dbdb569f4fa9d15340401fa9d653dbd14f0cd78093e40c532e53c04fdb56299fd1af6c69c3dab26f9a1ae9daecefaf32434f3a222f6094ba85d74fa3a2d5a0904646a3d5cf10d7a0a27520c54f30e698ec142fba05a23ae04fa0a2cf46a39055d79d3403afdd8327fe7e83ddb4a79d032f7413eb19e066104fc69e541ecd1a04efef54cd1e84c61a1e1e4d84d41aefc61e756768a1ea9289d420b17e7bee8182e940fd9d3bc76363efef1d477de3c0e33b88ac0502ac98f7ad747e7fefa27a0c9f5639c978358ce67a9c69ded006c6956b3b47e39d63ef40fd7a6f7e1f7f8ca2f4736bbaea087faf0303ba086b2f73ffea6b2fff08f3ea033a0288f4ad769856d1d1f47688d602982dadf6d67418d10288ea082f3aff0373eb982d08d1f4d6f60287050d8ec4390ace4e8dc4058a87390e058ab9c4070e4e8d22d3e7e5a38995ebebe723d395a289e5e5a395e789eb22d38e440a8d39ce87058965d3ebe795a3a29ac4d471f8e7a17b28c1f117ca7d02d3174a82f17dd328c1c4fbe66a8f328f63e3668f7b0fc4b2ea6a0f8fe6b263c4fbd3714a4182a8fd17b2eafbe3660f0fc4a25ca0df1522c80505a0955c4822a2df5c48a215a2df05a0b66649a35c1e68a727c9dc66e8361e23a35c68491ea7b666df154820a205a2dc1ea3662749e8dc36f4be8e6724cc5414940ea4be5474cc67be544c24f467948ea5cab7288de9ae7fff378dca2ea5e9a8288daeb7e97fa5ca67a4d40e4c14f4bee9a8caffb72e0da5986685e906a62f91118586e6af18a669e62fa6869869118544a61db63e0c33a1a19d3e26b3440c36b63eb31d0ca14426e9862f05269198e60c3626a11db3be4423a01ef459992889899e59a0a823197438411cdfb2928fb880077200fe0798707072fe0718800780ff969ae89c02749b125fc1389c8fb2b80780877072187e80ec988b49f87cec7afa0bf8186cecfcc998eb0e7812ce62fb8c0d1587a8b98e252595a88d0e8c398787a80e95b9258c0d4978ec8bfc7aec9839878d25958e288c9f9ad7e660b0d765e5d7e09a571fb0e69dcfb71e9f669525e489ec848141f459d9ec810974e4c1848401f4ecc159e489e69ecfa537151f9dc18489d96cf401e4ed1bcc7219c57b92124c999bfb6dc5729b7b4599ed7212cc9bfc2e8d9377fa39b9ae937c7a9b778d8d13faaef7399b7c72997b4c4592ed9b778dfcb92efa139b5037879f123027ac2c871237a750b01f3727b092d01f2c0717294a89b55da3fa7aca3529a3975d89893523caddfa17299f12270730ac50b75d09a97a4aa3b59728287f6fd6dbe2a3237f56a8e2a85befa8e25bd628ef237f83aaccf6d82c6f28a8ccd82a6f83ac76f658efcc2c2883aa6fd662ffdba32828acf62aa84cef58835c3a12765a83c7e565125abac75c03f6ba4703da5cf66512ada3b0b99f8e948383b09fa394ad8eb9b99f94b08e83ada376da471283e55c3a8eb9a383b0949fad07b65f5b54358bb6b65f54368b0735db360b35d407dbb65fc7f3428d84c8901393c284f310c7488d8d8490c2c813c7735b548b5fb5b60736488df393c29004c702c2491ff9f52ccf1b7f4f77f3b4ae183ef640a1c4d1a94d7d05706ec9b27d49497049857dfd326e6ec97df032497d055121f6cdc0a944be326e0549f07d49fdcbc48ea7fa34197633e269f9f7567ba22603f82515a2af293eec845b955955909004156cd5bed95b5b15d58459903eec17b641b9fce85d2dd95b6c90045595bee28e31ad4a45c48282b1ca0ec46245ad0e44c5ca62ad82b1db08e5751735374826acea664a5e7c47c76a4a2c7c26de66ad4ac431c582e20e25e6cf3be8f593a8d04adc66e295f783035ce2caf7d095e6caf715e2d0e603dce82ac02bafdd23515140afaa23e8dd2b2baf23c05d51e8aa66e277dc9583d0caddab2a51c0232fe860f6b093e7df31971389855a498cd14bc28ce4bbd68d847d0851600b0f63e80f0f600f516808638be5b26dbc2c4a9bbdf828431321990478630bd10f60680f083ee032f7fd0d05712e80c2c889f6b4f0f6c82a83cfca299ecc549eb776b06f8c273155ff076661ea08dbdfdd4d9e0a7bf086db51446cd2a45fd8a8b2073fb98c5ed3292016f74f0d47f9f0d0ad29abea4722b15556890d4efb473409f9adc64a4a702b16b63909e557525dbbfeb6f83b29bfd67adcc09d73199f7173bda3b3bc", "9e0355a7a7696a5fd3ed38922e7eae77025da69f6ba7556bee652f98d4ed07e0ee7493d2ad2f3a7e90d2ad3b7e762fee57a7a7695f02699ea59f6b576b5ea601c5136773c06621ccba7fce7cf785e20311cf71c423c06667681551449c2985d37e027ebbe3f7cd8415d14468859f51286773c022cc1167c573c4236467cdc11293e19b076c590bbe1ad9a3b9477f1d7ce3bf0790096e995b55686f762dcee25cc8187f7c1e3a18b2bb1b1da07d7d46db2a36b624e0b5766a2e155aca4ffa077cfa0a6177c1b14d49931b04dfb6a0d4cd094976f94ec161b3064e5888b36d9b4218ccdf92d7b504a3dc92d705a3ccb7186277c14d490ab1f975f94e61b349c209f4d790965cf6f5a3f1d951f20129e17dd5a094f4f75f92f651f201e17dd929f1d97df1f1e101512af1f1e1512a7d01d993965cf6a3d4f4f594f4f793f6a15cd626bebf758bb56479f19b8c8b8ed39417bc7b76276689bdb5566a8f6646b3318d981489f2978f8fd388f2978fd3148d9b2de3d793da6a43d1e3d3912e43d9d66b9d374864dca5c2b8b80284f602a0a10143dfec21bafaf71ba6226ce0f4ad40d50100f4baa20184a220d4e2a442f56dac36658deb49c48d7f649cc348a4badd35982663649cb872059c4ad98e7eb602fa26076498729d60b8da8e7e02fa48b59e4af98c9e027edab68d9e02dab6fa7c4a62649c700524bb9a67987261b8069c247f9519d248d7667f068534ba7e1a15ad967dd37c654b1bd631c764af03297e8285acba06157d361ab80615351aad7e86a3d42d7cd2117901d5017fa278d12d10ed1c78f11beca63dd6207837f6a4f2681e3cf1efa41978ed7837f6f06822a4d60f144c0789f5db7334d6f078a76af620378378a29b58cf00974ca4ae3b430b55071edf79ef38ea1bd563f8a4f3fb7b171e1b7b07eaefdc3930ae5ce34cf386366314a5d77bf3fbf86134d7b3ca49c6abc5bc6f45642d10607b07eadf391aef1c99fb571fd045587bc3b48a1640a46fb5f87b1d985bd355478816406cb5b7a6c3b7b617c06c4188a616c06c89a6b743b4571fd0597bf947981f985b574778d1f93ccc71706a242e504dac5c17993e2f1fce51703e2c6870245c17992e1fad3c4faf1c154d2c9b5e3f144d2c5f3f1f99ae70706a2c50cc253e713e2c70245268ccee139846098ebf5094791c23de37577b3f0fddd324a68ec31d23de577b7834977b78209655df1f372096551f377bdc7b9b4609be50128cef44edbf988e530a121211fd2e00ade442f2403bb5354b1ae510412e10e502fdae38b5351be5424bf242e7b6f118353b49b7f1183949e63643fd2e00e54212ad102d10e5feae400211a2633ea37420f5a54c77fd2b55be456961a6a2a0f7753c23ff2b55466974bd4d7569284d4755febf294d47fdbf6954763fa374f4a56222a1a2a0f73d23a57660c5304d8b2834347f6198092532edb0f5307d89c4342b4c37082532b1f599ed6098f52562b03109ed2562b009edf431994c8b28347f3135c489c4344f377c29301dc9a04bf4cc02453fc084033c9003f0ca44491c01f5a0cf14a0dbfcb7d444e7c3f0033c003c8493003c008493f33fc0957cc4c509e2f8967c94c595f80ac6e163e74fd65fc0c760cd752c616ca83844e763d763c75c4cc22d616c384475a8cc744461cc396c2ca960cc392ca9446d747016dbc75c77c093d763c74cc2635fe4fa80352fbf06d7bc0ca2cf224f64270c83bd2efbd4bc3607ce224f240ca0670fa30f200f264ccc66230f26cc660f4ca034ab2ce97cbef5f8a9f8e834f77c2ebd6f2b969360cadcdcbcd3cfd9e477699c28de936cdf6096cbcfd9e46b9cd077bdd19fd8bc6be4cf75dbbc6bcc759de4d3979360dedc2bca6c926cdf94cbdc632a8582fd603994b839ed1ad5bf48514aac80396185ba39fc94d6bf4849ac1951ee1aadbdec4a48d553bdec4ad453ae4919fe6039b8398195846185bafd9438398047dd7a1ff9b34215667943195465b6c7de161f4541f97bb3411954b5c77a67667ac71a64b55741651b64b54365c65679791ff94315dfb2461e454179b316fbdfe61ab02f93d0d23d74a41c6c1d85cdfd1a3c2ee7d291b0d31c6c1dcdfda48475a5fc6c75cc1d1d846c75cc1d84fd1ca5b22f93d03d1ad0e62ce7d2b1d33e92183ca8d9b6fda2b25944869c389e176a24aa59b43db0fddaa29e389e6b24841446862438466a9c9f1438466a9c14269c87d8b6fdb259a8a13eb53db0d9a25afcaaa775c5d8f87bba9b96ed4bea2b80734baf677916104efac849ea2b704bee8397ef4bea97712b4882eb97714b824b2aec8e4e6df2b1070a254e25f28d0ab16f06b7da139d114fcbbfccaa82f46127dcaaa7c9b05b26763cd582f461dfaaa826cca8aaf4cdde628324f6cdde8224a860ab107d4d3119c02fa947ef6ab9b00dcae5162b6a158c557620a8b941da4628afbb2a221614778c695533f1363b565362e1af9f442d317fde41f2e23b32615537536b158c75202a56161614776855228e2987ae341fe01257beed1e894257015e79afbc1f8456e236138a42575d791d01ee1e7941ef5e55890241ef5e89027a551d361fe056beaf10871c84563613bfe3ae628c5e9a482cd44a18437f4088025b78ff8eb904b3879d3c51daec2d976de365437b40185b887e0043185b7c007b88426e24ec136624dfb5c924c0c347199a08b4a785770114464e837d6364a6f2bcb56f2888f30197b9eff254d843d8feee6ef8c965fcc246953d300b533f89a9fa3f564ef1b44756197c6293268537dc8e224d59553fca87876e6f3556da3fa249c8b87f6af09a4e01b1b7c5dfb992eadaf51d9de5cdf88c9bebcd492857825bb1b04a6c703a1289adb206ee9c4bf9b5d6e3", "f173bd9b6ec791746e3f00772f7bc1a44d53fbf21ca83a3db37b7187946eddf1f3320d28fd5cbb5a7dd1f173a79b946e3bad5a13e832fd5c1248f3bc3a3d4dfb2f141fd0fd73e6bb4c299c46ab8822e2360b612e9e389b03fc8c42a98826422b6b0e9698231e213bbf6f26f413f0db1d01363b8b788e231e8e382b3e9b031661faebe0d3c81ecd3d7116e7aa427bb36bcb5af09d0cdf3c60eb33dadedde800edd23fe073a9d0527ed0c19045c6f8e3f370cbdc1aff3d804cafb55353b1b1250105a56e9edc20f8b66ddb143270c2429c8e6d4ad25708bb0b65bec5e096bc2e184d124ea8cb770a9bae2518c560fe96bc0a0e9b4d48b2cb775288cd17bb0b6e4a4809ef8bcf8e920fcb4e898f920f08efb2af1fa5bf86b4e4e90bc88e8f0f8f520fe5b2a6a4bf9fb40f8852c9ee8b8f0fff92b4af06a5a4bfa5a6af9fb4e4b21f9ca6bc88df645c749a8d69b4527b3433ac25cb33f1fdad5ba668dc4494bf7c9ccab65e1b9f8e74197c7c9cc6a44894bf4becade5ddb33b31561b8a6e19bf9ed4000d0dc01520b4176f05aa36156103a72e15c6edbc4122e3aa6f6305a1162715d5edae21e31c46220d20140d00a0d715d5bfdf18fa660fd1226efcb3296b5c4fb315d0e754ca76f447aaf5d476f413d0c4952bc0341923e3d5e7536af414d0b635e02439c3940bc3f0d3b655ca67f414eb04c3353920c39420d9d51423e3842bd3a8683528a4d1f548f1138c39267b1dba36fbfbabcc904668f533c435a8a8d18b6e81a80ef813c5e8b3d12864d535a85bdab0b6ec9be62b8ec80b18a56ee193279547b306c1bbb11321b5c6bbb187476037ed69e7c08bdf55b307a1b186c73b195aa8ba642275ddacdf9e7ba0603a48cdc06bf7e0897f27c47a06b819c413dddfdfbba81ec3279d9a37b48171e51a67c751df38f0f8ce7b4e325e0da3b99e55d178e7d83b50ffce9bdfc71fa328bdde7fe7cef1d8d83b506b81002be67d2b22227dab1da655b400bd351d46b40062ab2ec2dacbdcbffa80bd1da2b500664b34c28bceffc0dcba3a0b4234bdb5bd00669aae3ac2dfebc0dccb3fc2bcfa80cedaf479f96862e5bac868e579e2bac874f9237181e2618e8353f9c874a56862f9fa9142638ef3618123d9f4fa79e5a86862418323718e82f361622ef18183536381beb9daa3cce318f1c3a3b9ec18f1beda70fc85729fc0344ad9e3de03b1acfab89c5290206affc574fafeb8d9c303b1ac31751cfe79e89e2692607cdf344af08559d2289707daa9ad175a92c7a9add9286825179288e8770132b719ba8dc7c849051288688128f777a8d949123ab78dc717e8778508728128926885e877012817f22d4a63baeb5fa9a3eb6dfa5fa9324a03a92f151df319a54da3b24b693aeaff29b5031305bdef19aaf2ffad4b43693aafe31909331505bd151309fd19a5a32f6987ad0fc34c2891cf6c0743289189ada1a1f92b86695a44a78fc92c11834d68e14b814924a679ba8d4968c7ac2f11835961ba81e94b24a68ba921665a44a1f9811c80ff01261ce0a5263aa700dde6bf671628ea48065da29cff0106e001209c57300ee7a32caec4e0219c1c861fe001a8077d56264ae20810c7b7ace4232e4e43c5216aae630963aa43656e0963c321023e061b3b7fb2fe256aa30363ce61491efb22bf1e3b6612616349a5230a63cee662123e1fbb1e3bba039e84b3d83ee6223b6160107d1679003d7b701679226135b8e6d507ac79f97b60021d79306136e773e94dc547a7b96162361b7d007930e6b53918ec75d9a7f3adc7a7596549e7bf4be3e49d7ece2684beeb7dce265fe353e6e67e5bb19c04eb249fdee65d63aee61e539164fba65c237fae8bfec4e65d06b35c46f19e64fb5e5166bb9c04f3e68a52626dd7a8fe45cd8872b7fe454a62a1c4cd2914ec07cb724dcae86557a29ec4c9010c2bd4eda742aa9ed268ed6557cde1a704cc092bd409ac24f407cbc1cd2ab33d36cb1bcaa0d63b330bcaa0aa3d9f15aa38ead6fbc833b6cadb20ab1d2ab5d8fff6280aca9bbd0a2ad33bd620abcadf9bf5b6f8280af89635cafbc81faa286ceea723e560eb2725ace360eb68ee8496ee31d7807d99ece72865ab63ee20f691c46039978e9deee8202ce567ab638e849dd6e0713997d18036977d9984eebc50232132e4c4f121a430f2c4f15c231795cde241cdb6ed30e13cc43152e3a4d5e257aded81cd16e3fca43024c13152edd71655cda2ed81420df5c1b6ed97cd019c5bb26c5f525f721fbc4c525f815bdfd3dd3cad2bc6c65c52615fbf8c5b12887d33702a916f545b41127c5f52bf8c70d2477e3dcbb3803d502871746a938f3be156655615a40f45356116a40ffb56785afebdd59ee88c41055bb56ff616246d502e3f7a57cb85161b244155a56ff6b1e3a93e4d86dd32007e4985e86b8ac94279dd45cd0dd2369a120b9f89b7d9b1acb203b15851ab60abba999217df910912714cb1a0b843abf9f30e7afd246a89634cab5211b1a0b851b1b258ab60ac030af0ca6bf74814baeb08705714baeaca97b8f23d74a5f900d0abea087af74a14f81d77e520b4b299aa4a14f0c80b7af712b79978e5fd20b47d8538b4f900b7f214d8c2c318fa03426c1b2f8bd2666fb962a1561263f4d244d843141ac2d8e203cad0444826011e3e42f40318da03c2d83dece4f977cc259823f9ae7523619f3095e7ad1dec1b2333f6777793a7c21ec2a03072a23d2dbc0b4cd5ff815998fa49e17614119b3429bc36aaecc14f2ee317b8cc7d7f43419c0fb2cae0b3728aa73d114d427eabb1d2fe54d7aebf2dfece953e3c746bcaaafa51dc8a856d4e42b912afb51e3770e75cca67dc5cefe82c6fc6740a88c5fd5383d7486c95556283d391"]]], algorithm = { "scope": "Recovered public algorithm tables/permutations only. No packaged configuration, licence, common/sign material, device state or credentials.", "cipherProfiles": [{ "entryRva": "0x2b2b7c", "programmeRva": "0x1145c0", "keyExpansionScalar": "0xbbb5de72", "scalarInstructionRva": "0x1147bc", "observedLookupTableRva": "0xffcf9", "lookupTableSha256": "889cf0adbe6cae808b34a33ac85c9ecc73dd48a15af31df01b23f09a9feaaada", "lookupUniqueBytes": 256, "originalExpandedKeyByteExact": true, "permutationDerivedFromOriginalInitialState": [2, 0, 3, 1], "subShiftDerivedFromOriginalWriteStates": [8, 13, 6, 7, 0, 5, 10, 3, 12, 9, 2, 11, 4, 1, 14, 15], "middleColumnPermutationDerivedFromOriginalWriteStates": [2, 0, 3, 1], "firstMixWriteIndex": 27, "finalExtraKeyXor": true, "syntheticNativeBytes": 64, "syntheticByteExact": true, "publicSubstitutionHex": "53290fe9e51f316f90f74a7e034d367784ab49237cd0135cdc632c322fd3be0e2624a417ecd9151a7ff64f60730a87f9445ec6ada2f865d22b696c4188f24c0df37b75510b939f6bc2fe6883e68bc8c722181ba0bdb08c9871b50c9a16b46eea8eed20ba4b8a14e0fcf1468dbbef05a93e5a9d7dcf06898635c1fd99f5de287a80c594daaab19b6279fbd75070cb52eb2555c456e39e7839853874e2f0013ac0b64742d8ca10e4b79c955de8b843ce4ed464a6a72ed508091c92e7b3eedd1e1dd12afac321618fa3d65f9167c982f43d66a53c6a1997585b346dbf9672ff37cdbc073b2dae11453304df00815476b2a13fccdb30b957a8acafe1274002485912" }, { "entryRva": "0x2b2c28", "programmeRva": "0x1155a0", "keyExpansionScalar": "0xd4638d5b", "scalarInstructionRva": "0x11579c", "observedLookupTableRva": "0xffdf9", "lookupTableSha256": "5c3c71fa194c289c2ec0c77b5bc8f5fa38f2b2a11f4e8a27b34e1e4f625f9a89", "lookupUniqueBytes": 256, "originalExpandedKeyByteExact": true, "permutationDerivedFromOriginalInitialState": [1, 3, 2, 0], "subShiftDerivedFromOriginalWriteStates": [4, 9, 2, 11, 12, 1, 6, 7, 8, 5, 14, 3, 0, 13, 10, 15], "middleColumnPermutationDerivedFromOriginalWriteStates": [1, 3, 2, 0], "firstMixWriteIndex": 28, "finalExtraKeyXor": true, "syntheticNativeBytes": 64, "syntheticByteExact": true, "publicSubstitutionHex": "38922563e36406d37a24100b7902a028044e218453c2a399199c9d13dc40c55ba67e502273850ebdc1a2e2188b8f2d9e3cb909b8c46a2a9f4a6dd93007eafa65b7b3a881aa908cc74f0ad76bbbb58617c37012ca05a469fd44e62eecf1e4272ce860c0ae5eadf99b20d8f0234174006f3f110d7657d01645d4eff8f71471cbfe1cb2f52648727bf3c9de55153e031b4d61757db63dbf7782eeafe9018a8891362fb14759ac32bab03b349aeb5a377c5156be4c8dfbe13a684bda39cf836697c894545fe0f2491acea9fc6252f4ff1e0fe72bd2df6e67a7f635e5bcc6d1a5dd951d89960887a18eb40c785cdb1f80ed42299333ab98cdd67f316cd54346585dcc" }, { "entryRva": "0x2b2cb0", "programmeRva": "0x116590", "keyExpansionScalar": "0x92a5f73b", "scalarInstructionRva": "0x11678c", "observedLookupTableRva": "0xffef9", "lookupTableSha256": "0d2fc76c086837c8b40e55ed18e82f811c378ed4917a24098bdf37555080836d", "lookupUniqueBytes": 256, "originalExpandedKeyByteExact": true, "permutationDerivedFromOriginalInitialState": [3, 2, 1, 0], "subShiftDerivedFromOriginalWriteStates": [12, 5, 2, 15, 8, 1, 14, 3, 4, 13, 10, 7, 0, 9, 6, 11], "middleColumnPermutationDerivedFromOriginalWriteStates": [3, 2, 1, 0], "firstMixWriteIndex": 28, "finalExtraKeyXor": true, "syntheticNativeBytes": 64, "syntheticByteExact": true, "publicSubstitutionHex": "d759fb722789b08807cc0fda293f7e5e1819bb0353517020b31d3d00374952bea2c421e862040a9ec892a05b266b7a0d0cc316f483b81af39715657ffe32ad8de0c13077646035236ee5363e5f900e9a7cf850a81cd9960b6df73317226f99eaa6fff15cec34acb98246639b918ab2851466a7cdfc4ad1b52c2ae95a58d3734e47ddd5b7560193f644ef9c408b7dee39b4d6aabf4de761e3252d4c7ba3843187745d55e6a5db05d42b45caed43c0c5d0b64bfa9d94a4a9d8f2f0e1a108dcfd288fd2bc1fc7bd675412138169cb09249875ba3b68cfb11180afae104fc9789571c6dfce02413886796ae21e3c488cc21b9f423a066c2eabf98e2fdeeb5776e4f5" }, { "entryRva": "0x2b2d38", "programmeRva": "0x117580", "keyExpansionScalar": "0x89f8a1c9", "scalarInstructionRva": "0x11777c", "observedLookupTableRva": "0xffff9", "lookupTableSha256": "8457ad051d94ed79c99de112be6eb1dc2b60df7c0aeb606aad3ca6ae67e9660a", "lookupUniqueBytes": 256, "originalExpandedKeyByteExact": true, "permutationDerivedFromOriginalInitialState": [2, 3, 1, 0], "subShiftDerivedFromOriginalWriteStates": [8, 5, 2, 3, 12, 1, 10, 11, 4, 9, 14, 7, 0, 13, 6, 15], "middleColumnPermutationDerivedFromOriginalWriteStates": [2, 3, 1, 0], "firstMixWriteIndex": 28, "finalExtraKeyXor": true, "syntheticNativeBytes": 64, "syntheticByteExact": true, "publicSubstitutionHex": "d09a515ba58cbbab3e37b09fd4f6d9244df80512e84cd7956be301cf64f1429d58577cc241f3a2c655144f81aaf95a4e108da894b38970561ae9002619fbbac91fa922ed202bfc62cb08e0de2a7f3631435f8b47c8a3c563b4db4071ce74c46da6fa696a9e282d1e825d663b93bfd56c48dce1884bb10fccea063929f746443fd830a4232e53da21a1f2d1bdfebc3a02c10a1b8ad31d04fd616590d272ac737e98eb33af60528716bee78ec0ee8699031177277d9cff32542c67caf5f44591681335ae0e178f3409a7803db83892dde5b9b7f0c750e24aef077badd678a09b850b84ec1597e4963cb5e675df1c0d6fb618496ecd76c35c798325590c2fb27a5e" }], "planes": [{ "plane": 0, "outputBitToSourceBit": { "0": 47, "1": 6, "2": 34, "3": 19, "4": 49, "5": 56, "6": 28, "7": 13 } }, { "plane": 1, "outputBitToSourceBit": { "0": 40, "1": 7, "2": 35, "3": 20, "4": 50, "5": 57, "6": 29, "7": 14 } }, { "plane": 2, "outputBitToSourceBit": { "0": 41, "1": 0, "2": 36, "3": 21, "4": 51, "5": 58, "6": 30, "7": 15 } }, { "plane": 3, "outputBitToSourceBit": { "0": 42, "1": 1, "2": 37, "3": 22, "4": 52, "5": 59, "6": 31, "7": 8 } }, { "plane": 4, "outputBitToSourceBit": { "0": 43, "1": 2, "2": 38, "3": 23, "4": 53, "5": 60, "6": 24, "7": 9 } }, { "plane": 5, "outputBitToSourceBit": { "0": 44, "1": 3, "2": 39, "3": 16, "4": 54, "5": 61, "6": 25, "7": 10 } }, { "plane": 6, "outputBitToSourceBit": { "0": 45, "1": 4, "2": 32, "3": 17, "4": 55, "5": 62, "6": 26, "7": 11 } }, { "plane": 7, "outputBitToSourceBit": { "0": 46, "1": 5, "2": 33, "3": 18, "4": 48, "5": 63, "6": 27, "7": 12 } }] };
              const join = (...parts) => {
                const output = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
                let offset = 0;
                for (const part of parts) {
                  output.set(part, offset);
                  offset += part.length;
                }
                return output;
              };
              const rotate = (value, count) => (value << count | value >>> 32 - count) >>> 0;
              function sha1(data) {
                const size = Math.ceil((data.length + 9) / 64) * 64;
                const input = new Uint8Array(size);
                input.set(data);
                input[data.length] = 128;
                const view = new DataView(input.buffer);
                view.setUint32(size - 8, Math.floor(data.length / 536870912));
                view.setUint32(size - 4, data.length * 8 >>> 0);
                const h = [1732584193, 4023233417, 2562383102, 271733878, 3285377520];
                const words = new Uint32Array(80);
                for (let offset = 0; offset < size; offset += 64) {
                  for (let i = 0; i < 16; i++) words[i] = view.getUint32(offset + i * 4);
                  for (let i = 16; i < 80; i++) words[i] = rotate(words[i - 3] ^ words[i - 8] ^ words[i - 14] ^ words[i - 16], 1);
                  let [a, b, c, d, e] = h;
                  for (let i = 0; i < 80; i++) {
                    const f = i < 20 ? b & c | ~b & d : i < 40 ? b ^ c ^ d : i < 60 ? b & c | b & d | c & d : b ^ c ^ d;
                    const k = i < 20 ? 1518500249 : i < 40 ? 1859775393 : i < 60 ? 2400959708 : 3395469782;
                    const next = rotate(a, 5) + f + e + k + words[i] >>> 0;
                    e = d;
                    d = c;
                    c = rotate(b, 30);
                    b = a;
                    a = next;
                  }
                  for (const [i, value] of [a, b, c, d, e].entries()) h[i] = h[i] + value >>> 0;
                }
                const result = new Uint8Array(20), output = new DataView(result.buffer);
                h.forEach((value, i) => output.setUint32(i * 4, value));
                return result;
              }
              function rc4(data, key) {
                if (!key.length) throw Error("Empty key");
                const state = Uint8Array.from({ length: 256 }, (_, i2) => i2);
                let i = 0, j = 0;
                for (i = 0; i < 256; i++) {
                  j = j + state[i] + key[i % key.length] & 255;
                  [state[i], state[j]] = [state[j], state[i]];
                }
                i = 0;
                j = 0;
                return Uint8Array.from(data, (value) => {
                  i = i + 1 & 255;
                  j = j + state[i] & 255;
                  [state[i], state[j]] = [state[j], state[i]];
                  return value ^ state[state[i] + state[j] & 255];
                });
              }
              function createConfigurationDecoder(crypto) {
                return (encoded, appid) => {
                  if (typeof encoded !== "string" || encoded.length > 131072 || encoded.length % 4 || !/^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) throw Error("Invalid base64");
                  const data = crypto.base64(encoded);
                  if (data.length < 20 || (data.length - 4) % 16) throw Error("Invalid outer size");
                  const app = crypto.utf8(appid), prefix = data.slice(0, 4);
                  const key = crypto.md5(join(app, prefix, app));
                  const padded = new Uint8Array(data.length - 4);
                  for (let i = 4; i < data.length; i += 16) padded.set(crypto.decryptBlock(data.slice(i, i + 16), key), i - 4);
                  const padding = padded.at(-1);
                  if (padding < 1 || padding > 16 || padded.slice(-padding).some((v) => v !== padding)) throw Error("Invalid padding");
                  const plain = padded.slice(0, -padding);
                  if (plain.length < 8) throw Error("Invalid inner framing");
                  const head = plain.slice(0, 4), tail = plain.slice(-4);
                  const inner = rc4(plain.slice(4, -4), sha1(join(head, app, prefix)));
                  const mask = join(prefix, head, tail).reduce((a, b) => a ^ b, 0);
                  return Uint8Array.from(inner.reverse(), (value) => value ^ mask);
                };
              }
              function word64(value) {
                const text = String(value);
                if (/^0x[0-9a-f]{1,16}$/i.test(text)) {
                  const hex = text.slice(2).padStart(16, "0");
                  return [parseInt(hex.slice(0, 8), 16) >>> 0, parseInt(hex.slice(8), 16) >>> 0];
                }
                if (!/^\d+$/.test(text)) throw Error("V5_INTEGER");
                let high = 0, low = 0;
                for (let i = 0; i < text.length; i++) {
                  const next = low * 10 + Number(text[i]);
                  high = high * 10 + Math.floor(next / 4294967296);
                  if (high > 4294967295) throw Error("V5_INTEGER_RANGE");
                  low = next >>> 0;
                }
                return [high >>> 0, low];
              }
              function wordXor(a, b) {
                return [(a[0] ^ b[0]) >>> 0, (a[1] ^ b[1]) >>> 0];
              }
              function wordByte(value, shift) {
                return value[shift < 32 ? 1 : 0] >>> (shift & 31) & 255;
              }
              function wordNumber(value) {
                return value[0] * 4294967296 + value[1];
              }
              function wordEquals(a, b) {
                return a[0] === b[0] && a[1] === b[1];
              }
              function ror(value, n) {
                n &= 63;
                if (!n) return value;
                if (n >= 32) {
                  value = [value[1], value[0]];
                  n -= 32;
                }
                return n ? [(value[0] >>> n | value[1] << 32 - n) >>> 0, (value[1] >>> n | value[0] << 32 - n) >>> 0] : value;
              }
              function bigRead(bytes, at, little = false) {
                let high = 0, low = 0;
                for (let i = 0; i < 8; i++) {
                  const value = bytes[at + (little ? 7 - i : i)];
                  if (i < 4) high = (high << 8 | value) >>> 0;
                  else low = (low << 8 | value) >>> 0;
                }
                return [high, low];
              }
              function readWordVarint(data, state, invalid, truncated = invalid) {
                let high = 0, low = 0;
                for (let i = 0; i < 10; i++) {
                  if (state.offset >= data.length) throw Error(truncated);
                  const byte = data[state.offset++], bits = byte & 127, shift = i * 7;
                  if (i === 9 && bits > 1) throw Error(invalid);
                  if (shift < 32) {
                    low = (low | bits << shift) >>> 0;
                    if (shift > 25) high = (high | bits >>> 32 - shift) >>> 0;
                  } else high = (high | bits << shift - 32) >>> 0;
                  if (byte < 128) return [high, low];
                }
                throw Error(invalid);
              }
              const tables = new Map(tableData.map(([selector, rows]) => [selector, rows.map((text) => {
                const bytes = S.from(text, "hex");
                return Array.from({ length: 256 }, (_, i) => bigRead(bytes, i * 8, true));
              })]));
              function rawChecksum(data, seed = 0, count = data.length) {
                let e = seed >>> 0;
                for (let i = 0; i < count; i++) {
                  let n = i & 1 ? e >>> 5 ^ e : e >>> 3 ^ e;
                  let v = i & 1 ? ~(data[i] | e << 11) : data[i] ^ e << 7;
                  e = (v ^ n) >>> 0;
                }
                return e;
              }
              function thirdHead(selector, data, epoch) {
                const profile = third.find((r) => r.selector === selector), C = profile.publicScalar, T = tables.get(selector);
                let h = Array(8).fill(ror(word64(epoch), epoch + C - 1 & 63)), rc = literalRows.map((v) => ror(v, epoch + C & 63));
                const padded = S.concat([data, S.from([128]), S.alloc(43), S.alloc(32)]);
                padded[126] = 1;
                padded[127] = 160;
                const transform = (v) => Array.from({ length: 8 }, (_, i) => T.reduce((out, t, j) => wordXor(out, t[wordByte(v[i - j & 7], 56 - 8 * j)]), [0, 0]));
                for (let index = 0; index < 2; index++) {
                  const block2 = Array.from({ length: 8 }, (_, i) => bigRead(padded, index * 64 + i * 8));
                  let key = index ? profile.paddedBlockKeyHashPermutation.map((i) => h[i]) : h.slice();
                  let state = index ? key.slice() : key.map((v, i) => wordXor(v, block2[profile.firstBlockInputPermutation[i]]));
                  if (index) state[profile.paddedBlockLengthXorCanonicalIndex] = wordXor(state[profile.paddedBlockLengthXorCanonicalIndex], [0, 416]);
                  for (let i = 1; i <= 10; i++) {
                    key = transform(key);
                    key[0] = wordXor(key[0], rc[i]);
                    state = transform(state).map((v, j) => wordXor(v, key[j]));
                  }
                  h = h.map((v, i) => wordXor(wordXor(v, state[i]), block2[i + 1 & 7]));
                }
                const packed = S.from(h.slice().reverse().flatMap((v) => [8, 24, 40, 48].map((s) => wordByte(v, s))));
                return S.from(Array.from({ length: 16 }, (_, i) => packed[i] ^ packed[i + 16]));
              }
              function decodeFields(data) {
                const state = { offset: 0 }, fields = /* @__PURE__ */ new Map();
                const read = () => readWordVarint(data, state, "V5_PROTO_VARINT", "V5_PROTO_TRUNCATED");
                while (state.offset < data.length) {
                  const tag = wordNumber(read()), field = tag >>> 3, wire = tag & 7;
                  if (wire === 0) fields.set(field, read());
                  else if (wire === 2) {
                    const length = wordNumber(read());
                    if (length > data.length - state.offset) throw Error("V5_PROTO_LENGTH");
                    fields.set(field, data.subarray(state.offset, state.offset + length));
                    state.offset += length;
                  } else throw Error("V5_PROTO_WIRE");
                }
                return fields;
              }
              function extract(data) {
                const bytes = [];
                for (const plane of algorithm.planes) {
                  for (let word = 0; word < Math.floor(data.length / 8); word++) {
                    let value = 0;
                    for (const [d, s] of Object.entries(plane.outputBitToSourceBit)) value |= (data[word * 8 + Math.floor(s / 8)] >>> s % 8 & 1) << Number(d);
                    bytes.push(value);
                    if (bytes.length === 31) return S.from(bytes);
                  }
                }
                return S.from(bytes);
              }
              function embed(data, coded) {
                const output = S.from(data);
                let index = 0;
                for (const plane of algorithm.planes) {
                  for (let word = 0; word < Math.floor(data.length / 8); word++) {
                    for (const [d, s] of Object.entries(plane.outputBitToSourceBit)) {
                      const at = word * 8 + Math.floor(s / 8), m = 1 << s % 8;
                      output[at] = output[at] & ~m | (coded[index] >>> Number(d) & 1) * m;
                    }
                    if (++index === 31) return output;
                  }
                }
                return output;
              }
              function expand(key, substitution, scalar) {
                const output = new Uint8Array(48);
                for (let i = 0; i < 16; i++) output[i] = key[i] ^ scalar >>> i % 4 * 8 & 255;
                let counter = 8;
                for (let word = 4; word < 12; word++) {
                  const previous = 4 * (word - 1);
                  let [a, b, c, d] = output.slice(previous, previous + 4);
                  if (word % 4 === 0) [a, b, c, d] = [(scalar >>> (counter & 24) ^ substitution[b]) & 255, substitution[c], substitution[d], substitution[a]];
                  counter += 2;
                  [a, b, c, d].forEach((v, i) => output[previous + 4 + i] = v ^ output[previous - 12 + i]);
                }
                return output;
              }
              function block(data, key, profile) {
                const box = S.from(profile.publicSubstitutionHex, "hex"), keys = expand(key, box, Number(profile.keyExpansionScalar)), perm = profile.permutationDerivedFromOriginalInitialState, middle = profile.middleColumnPermutationDerivedFromOriginalWriteStates, shift = profile.subShiftDerivedFromOriginalWriteStates;
                let state = Array.from(data);
                const add = (start) => {
                  for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) state[r * 4 + c] ^= keys[(start + r) * 4 + perm[c]];
                };
                add(0);
                for (let round = 1; round <= 2; round++) {
                  state = shift.map((i) => box[state[i]]);
                  if (round === 1) {
                    state = state.map((v, i, a) => a[Math.floor(i / 4) * 4 + middle[i % 4]]);
                    const twice = (v) => (v << 1 ^ (v & 128 ? 27 : 0)) & 255;
                    for (let c = 0; c < 4; c++) {
                      const total = state[c] ^ state[4 + c] ^ state[8 + c] ^ state[12 + c], first = state[c];
                      for (let r = 0; r < 3; r++) state[r * 4 + c] ^= total ^ twice(state[r * 4 + c] ^ state[(r + 1) * 4 + c]);
                      state[12 + c] ^= total ^ twice(state[12 + c] ^ first);
                    }
                  }
                  add(round * 4);
                }
                for (let r = 0; r < 4; r++) for (let c = 0; c < 4; c++) state[r * 4 + c] ^= keys[(4 + r) * 4 + c];
                return S.from(state);
              }
              function cipher(data, key, iv, profile) {
                const padding = 16 - data.length % 16, input = S.concat([data, S.alloc(padding, padding)]), result = [];
                let previous = iv;
                for (let i = 0; i < input.length; i += 16) {
                  const bytes = S.from(Array.from(input.subarray(i, i + 16), (v, j) => v ^ previous[j]));
                  previous = block(bytes, key, profile);
                  result.push(previous);
                }
                return S.concat(result);
              }
              function packet(input) {
                const proto = S.from(input.protoHex, "hex"), material = S.from(input.materialHex, "hex"), randoms = input.randoms, epoch = input.epoch, fields = decodeFields(proto);
                if (![32, 64].includes(material.length) || !Array.isArray(randoms) || randoms.length !== 3 || !randoms.every(Number.isSafeInteger) || !Number.isSafeInteger(epoch) || epoch < 0 || epoch > 4294967295) throw Error("V5_INPUT_SHAPE");
                if (!wordEquals(fields.get(2), word64(10)) || !wordEquals(fields.get(3), word64(randoms[0] * 2)) || !wordEquals(fields.get(12), word64(epoch * 2))) throw Error("V5_INPUT_BINDING");
                let digest = components({ queryHex: input.queryHex, bodyHex: input.bodyHashHex, epoch });
                let normalJni = false;
                if (digest.mixedDigestHex !== fields.get(13).toString("hex")) {
                  normalJni = true;
                  digest = components({ queryHex: input.queryHex, bodyHex: input.bodyHashHex, epoch, normalJni });
                }
                if (digest.mixedDigestHex !== fields.get(13).toString("hex") || digest.queryHashHex.slice(0, 12) !== fields.get(14).toString("hex")) throw Error("V5_DIGEST_BINDING");
                const nonce = randoms[1], stream = components({ queryHex: input.queryHex, bodyHex: input.bodyHashHex, epoch, normalJni, protoHex: input.protoHex, materialHex: input.materialHex, nonce }), prefix = fields.get(10), seed = S.from(stream.streamKeyHex, "hex"), body = S.concat([prefix, S.from(stream.xiHex, "hex")]).reverse();
                for (let i = 0; i < body.length; i++) body[i] ^= seed[~i & 3];
                const q = S.from(digest.queryHashHex, "hex"), d = S.from(digest.mixedDigestHex, "hex"), flags = (q[0] & 63) << 14 | 402653185 | (d[0] & 63) << 8, head = S.alloc(9), tail = S.alloc(4);
                head[0] = stream.prefixFlag;
                head.writeUInt32LE(randoms[2] >>> 0, 1);
                head.writeUInt32LE(flags >>> 0, 5);
                tail.writeUInt32LE(nonce >>> 0);
                const data = S.concat([head, body, tail.subarray(2)]), extracted = extract(data);
                if (extracted.length !== 31) throw Error("V5_EXTRACTION_SIZE");
                const md5 = (bytes) => K.createHash("md5").update(bytes).digest(), coded = cipher(extracted, md5(material.subarray(0, 16)), md5(material.subarray(16, 32)), algorithm.cipherProfiles[epoch & 3]), header = S.concat([S.from([5, 0, 0, 0]), fields.get(1)]);
                for (let i = 0; i < 20; i += 4) header.writeUInt32LE((header.readUInt32LE(i) ^ epoch) >>> 0, i);
                const meta = S.alloc(4);
                meta.writeUInt16LE(nonce & 65535);
                meta[3] = coded.length - 31;
                return S.concat([header, meta, coded.subarray(31), embed(data, coded)]).toString("base64");
              }
              function components(input) {
                var _a, _b;
                const { queryHex, bodyHex, epoch, materialHex, nonce, protoHex, normalJni = false } = input;
                const q = (_a = input.queryHashHex) != null ? _a : pComponents.hash(queryHex), selector = (_b = input.selectorOverride) != null ? _b : pComponents.selector(q, bodyHex, epoch) & 15;
                let head;
                if (selector % 3 === 2) head = S.from(pComponents.md5(selector, q, bodyHex, epoch), "hex");
                else if (selector % 3 === 0) head = S.from(pComponents.sha(selector, q, bodyHex, epoch), "hex");
                else {
                  const time = S.alloc(4);
                  time.writeUInt32LE(epoch >>> 0);
                  head = thirdHead(selector, S.concat([S.from(q, "hex"), S.from(bodyHex, "hex"), time]), epoch);
                }
                let sum = rawChecksum(head, 539100192, normalJni ? 12 : 8);
                sum = normalJni ? ((sum | 4 | 32) ^ 16777216) >>> 0 : (sum & ~4 & ~32 ^ 16777216) >>> 0;
                const check = S.alloc(4);
                check.writeUInt32LE(sum);
                const digest = S.concat([head, check]);
                let result = { queryHashHex: q, selector, mixedDigestHex: digest.toString("hex") };
                if (materialHex !== void 0) {
                  const material = S.from(materialHex, "hex"), seed = pComponents.zi(materialHex, nonce);
                  result = { ...result, prefixFlag: rawChecksum(material) & 255, streamSeedHex: seed[0], streamKeyHex: seed[1] };
                  if (protoHex !== void 0) result.xiHex = pComponents.xi(protoHex, seed[0]);
                }
                return result;
              }
              function PublicProfileHelios(r, publicId) {
                let e = Math.floor(Math.random() * 4294967296), t = S.concat([Z(e), S.from("8662")]), n = K.createHash("md5").update(t).digest(), i = S.from(n.toString("hex"), "ascii"), o = [];
                for (let d = 0; d < 4; d += 1) o.push(Dt(i, d * 8));
                let a = [o[0]], c = o[0], s = o[1];
                o.splice(0, 2);
                for (let d = 0; d < 34; d += 1) {
                  let x = sn(ft(s, 8), c);
                  x = st(x, [d, 0]), o.push(x), x = st(x, ft(c, 61)), a.push(x), c = x, s = o.shift();
                }
                let u = S.from(`${r}-${publicId.toString("ascii")}-8662`), f = S.alloc(Math.ceil((u.length + 1) / 16) * 16, 16 - u.length % 16);
                u.copy(f);
                let h = [];
                for (let d = 0; d < f.length; d += 16) {
                  let x = Dt(f, d), y = Dt(f, d + 8);
                  for (let F = 0; F < 34; F += 1) y = st(a[F], sn(x, ft(y, 8))), x = st(y, ft(x, 61));
                  let I = S.alloc(16);
                  fn(I, x, 0), fn(I, y, 8), h.push(I);
                }
                return S.concat([Z(e), ...h]).toString("base64");
              }
              function PublicProfileGorgon(r, e, t, n) {
                let i = S.alloc(4);
                i.writeUInt32LE(67764992);
                let o = S.concat([K.createHash("md5").update(r).digest().subarray(0, 4), e ? K.createHash("md5").update(e).digest().subarray(0, 4) : S.alloc(4), S.alloc(4), i, gn(t)]), a = [74, 64, 22, n >> 8 & 255, 71, 108, 1, n & 255], c = $i([...o], a);
                for (let s = 0; s < c.length; s += 1) {
                  let u = c[s];
                  u = (u >> 4 | u << 4) & 255;
                  let f = s + 1 < c.length ? c[s + 1] : c[0];
                  c[s] = ~(Vi((f ^ u) & 255) ^ 20) & 255;
                }
                return S.concat([S.from("8404", "hex"), S.from([n & 255, n >> 8 & 255, 64, 1]), c]).toString("hex");
              }
              function encodeWordVarint(value) {
                let high = value[0], low = value[1], out = [];
                while (high || low > 127) {
                  out.push(low & 127 | 128);
                  low = (low >>> 7 | high << 25) >>> 0;
                  high >>>= 7;
                }
                out.push(low);
                return S.from(out);
              }
              function profileVarint(value) {
                return encodeWordVarint(word64(value));
              }
              function profileInteger(field, value) {
                const text = String(value), negative = text[0] === "-", n = word64(negative ? text.slice(1) : text);
                let high = (n[0] << 1 | n[1] >>> 31) >>> 0, low = n[1] << 1 >>> 0;
                if (negative && (n[0] || n[1])) {
                  if (!low) high = high - 1 >>> 0;
                  low = low - 1 >>> 0;
                }
                return S.concat([profileVarint(field * 8), encodeWordVarint([high, low])]);
              }
              function profileBytes(field, value) {
                const data = typeof value === "string" ? S.from(value, "utf8") : S.from(value);
                return S.concat([profileVarint(field * 8 + 2), profileVarint(data.length), data]);
              }
              function profileConfiguration(encoded) {
                var _a, _b, _c, _d;
                const decode = createConfigurationDecoder({ utf8: (text) => S.from(text, "utf8"), base64: (text) => S.from(text, "base64"), md5: (value) => K.createHash("md5").update(value).digest(), decryptBlock: (data, key) => {
                  const c = K.createDecipheriv("aes-128-cbc", S.from(key), S.alloc(16));
                  c.setAutoPadding(false);
                  return S.concat([c.update(data), c.final()]);
                } });
                const fields = decodeFields(S.from(decode(encoded, "8662")));
                if (((_a = fields.get(2)) == null ? void 0 : _a.toString()) !== "mssdk" || ((_b = fields.get(5)) == null ? void 0 : _b.toString()) !== "8662") throw Error("LOCAL_PROFILE_INVALID");
                const id = fields.get(3);
                if (!id || id.length < 1 || id.length > 128) throw Error("LOCAL_PROFILE_INVALID");
                const rows = S.from(decode(encoded, "8662")), state = { offset: 0 };
                let material;
                const read = () => wordNumber(readWordVarint(rows, state, "LOCAL_PROFILE_INVALID"));
                while (state.offset < rows.length) {
                  const tag = read(), field = tag >>> 3, wire = tag & 7;
                  if (wire === 0) {
                    read();
                    continue;
                  }
                  if (wire !== 2) throw Error("LOCAL_PROFILE_INVALID");
                  const length = read();
                  if (length > rows.length - state.offset) throw Error("LOCAL_PROFILE_INVALID");
                  const value = rows.subarray(state.offset, state.offset + length);
                  state.offset += length;
                  if (field === 8) {
                    const item = decodeFields(value);
                    if (((_c = item.get(1)) == null ? void 0 : _c.toString()) === "sign_key") {
                      if (material) throw Error("LOCAL_PROFILE_INVALID");
                      material = S.from(((_d = item.get(2)) == null ? void 0 : _d.toString()) || "", "base64");
                    }
                  }
                }
                if (!material || material.length !== 32) throw Error("LOCAL_PROFILE_INVALID");
                return { id: S.from(id), material };
              }
              function createLocalSigningProfile(encoded, sdkVersion) {
                return createSigningProfile(profileConfiguration(encoded), sdkVersion);
              }
              function createSigningProfile(configuration, sdkVersion) {
                var _a;
                if (sdkVersion !== "v04.10.03-ml-android") throw Error("LOCAL_PROFILE_UNSUPPORTED");
                if (!configuration || !configuration.id || configuration.id.length < 1 || configuration.id.length > 128 || ((_a = configuration.material) == null ? void 0 : _a.length) !== 32) throw Error("SIGNING_CONFIGURATION_INVALID");
                let sequence = 0;
                function produce(input) {
                  const { url, epoch, device, randoms } = input, query = url.slice(url.indexOf("?") + 1), body = input.bodyBase64 == null ? null : S.from(input.bodyBase64, "base64"), bodyHash = body === null ? S.alloc(16) : K.createHash("md5").update(body).digest();
                  const counter = input.counter == null ? ++sequence : input.counter;
                  if (!Number.isSafeInteger(counter) || counter < 1 || counter > 2147483647) throw Error("LOCAL_PROFILE_STATE");
                  const did = String(device.device_id || "");
                  if (!/^[1-9][0-9]{9,23}$/.test(did)) throw Error("LOCAL_PROFILE_DEVICE");
                  const digest = components({ queryHex: S.from(query).toString("hex"), bodyHex: bodyHash.toString("hex"), epoch }), state = S.concat([profileInteger(1, counter), profileInteger(2, 694367), profileInteger(3, 694367), profileInteger(5, 694367)]);
                  const proto = S.concat([profileBytes(1, S.from("2d4b4fca49750d433fb5ae2c226dcc56", "hex")), profileInteger(2, 5), profileInteger(3, randoms[0]), profileBytes(4, "8662"), profileBytes(5, did), profileBytes(6, configuration.id), profileBytes(8, sdkVersion), profileInteger(9, 67764992), profileBytes(10, S.alloc(8)), profileInteger(12, epoch), profileBytes(13, S.from(digest.mixedDigestHex, "hex")), profileBytes(14, S.from(digest.queryHashHex, "hex").subarray(0, 6)), profileBytes(15, state), profileInteger(17, epoch)]);
                  return { proto, body, query, signature: packet({ protoHex: proto.toString("hex"), materialHex: configuration.material.toString("hex"), randoms, queryHex: S.from(query).toString("hex"), bodyHashHex: bodyHash.toString("hex"), epoch }) };
                }
                return { produce, sign(input) {
                  const randoms = Array.from({ length: 3 }, () => K.randomBytes(4).readUInt32LE(0) & 2147483647), p = produce({ ...input, randoms });
                  return { "x-gorgon": PublicProfileGorgon(p.query, p.body, input.epoch, Math.floor(Math.random() * 65536)), "x-khronos": String(input.epoch), "x-ladon": gn(input.epoch).toString("base64"), "x-argus": Z(input.epoch).toString("base64"), "x-helios": PublicProfileHelios(input.epoch, configuration.id), "x-medusa": p.signature };
                } };
              }
              const builtInConfiguration = { id: "NjQ2NjM3Nzk0", material: "sjwqRwog0QXcP4xEOPgnLtRtbIn/3N7dUQhpjSbpSJ0=" };
              const builtInProfile = builtInConfiguration.id.startsWith("__THL_") ? null : createSigningProfile({ id: S.from(builtInConfiguration.id, "base64"), material: S.from(builtInConfiguration.material, "base64") }, "v04.10.03-ml-android");
              globalThis.__hongguoHasBuiltInSigning = true;
              globalThis.__hongguoUseLocalApkProfile = function() {
              };
              globalThis.__hongguoLocalSign = function(url, body, epoch, device) {
                if (!builtInProfile) throw Object.assign(new Error("\u6570\u636E\u6E90\u672A\u914D\u7F6E\u72EC\u7ACB\u7B7E\u540D\u53C2\u6570\uFF0C\u8BF7\u5728\u5E94\u7528\u5185\u8FD0\u884C\u5185\u7F6E\u6570\u636E\u6E90"), { code: "SOURCE_CONFIGURATION_MISSING" });
                return builtInProfile.sign({ url, bodyBase64: body == null ? null : body.toString("base64"), epoch, device });
              };
            })();
            function Ht(r, e = xn, t = {}, n) {
              let i = { ...yn, ...n || { iid: an(), device_id: an() } }, o = Math.floor(Date.now() / 1e3), a = r == null ? null : S.from(r), c = Date.now(), s = c, u = "", f = "";
              for (let x = 0; x < 32; x += 1) {
                s = c + x;
                let y = { ...i, ...t, ts: String(o), _rticket: String(s) };
                if (u = Ni(y), f = `${e}?${u}`, to(f, a, o) !== 1) break;
              }
              let h = Math.floor(Math.random() * 65536), local = globalThis.__hongguoLocalSign(f, a, o, i), d = { "User-Agent": dt, Accept: "application/json; charset=utf-8,application/x-protobuf", "Content-Type": "application/json; charset=UTF-8", "x-xs-from-web": "0", "x-ss-req-ticket": String(s), "x-tt-request-tag": "t=0;n=0", "sdk-version": "2", "passport-sdk-version": "50561", "x-vc-bdturing-sdk-version": "3.7.2.cn", "x-ss-stub": Ti(a || ""), ...local || { "x-gorgon": Wi(u, a, o, h), "x-khronos": String(o), "x-ladon": gn(o).toString("base64"), "x-argus": Z(o).toString("base64"), "x-helios": eo(o), "x-medusa": Qi(f, a, o, i) }, "x-tt-dt": "" };
              return a || delete d["x-ss-stub"], { url: f, headers: d, body: a };
            }
            function ro(r) {
              var _a;
              return typeof r == "string" ? ((_a = Lt(r)) == null ? void 0 : _a.fallback_api) || r : Array.isArray(r) ? fe(r[0]) : fe(r == null ? void 0 : r.fallback_api);
            }
            function no(r) {
              let e = S.from(fe(r).replace(/-/g, "+").replace(/_/g, "/"), "base64");
              if (e.length < 3) throw new Error("spade_a too short");
              let t = e.length - (e[0] ^ e[1] ^ e[2]) + 47;
              if (t = Math.min(t, e.length - 1), t < 33) throw new Error("spade_a key length invalid");
              let n = S.from(e.subarray(1, 1 + t)), i = 85, o = 246;
              for (let c = 0; c < t; c += 1) {
                let s = n[c], u = c & 1 ? i : o;
                c & 1 ? i = s : o = s;
                let f = c.toString(2).split("1").length - 1;
                n[c] = -21 - f + (u ^ s) & 255;
              }
              let a = n.subarray(1, 33).toString("ascii");
              if (!/^[0-9a-f]{32}$/i.test(a)) throw new Error("App \u89C6\u9891\u5BC6\u94A5\u683C\u5F0F\u65E0\u6548");
              return S.from(a, "hex");
            }
            function io(r, e) {
              let t = fe(r);
              if (!t) return "";
              let n = S.from(t, "base64");
              if (n.length < 5) throw new Error("spade URL ciphertext too short");
              if (n[0] !== 168 || n[2] !== 1 || n[3] !== 0) throw new Error("spade URL header format error");
              let i = Math.floor((n.length - 4) / 16) * 16;
              if (!i) throw new Error("spade URL ciphertext has no complete block");
              let o = S.from("4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58", "hex"), a = K.createHash("sha512").update(e).digest(), c = K.createHash("sha512").update(S.concat([a, o])).digest(), s = K.createDecipheriv("aes-128-cbc", c.subarray(0, 16), c.subarray(16, 32));
              s.setAutoPadding(false);
              let u = S.concat([s.update(n.subarray(4, 4 + i)), s.final()]);
              if (u.length) {
                let f = u[u.length - 1];
                f >= 1 && f <= 16 && f <= u.length && (u = u.subarray(0, u.length - f));
              }
              for (; u.length && u[u.length - 1] === 0; ) u = u.subarray(0, u.length - 1);
              return u.toString("utf8");
            }
            function lt(r, e) {
              let t;
              try {
                t = new dn(r);
              } catch (e2) {
                throw Object.assign(new Error("App \u7247\u6E90\u5730\u5740\u683C\u5F0F\u65E0\u6548"), { code: "INVALID_RESPONSE" });
              }
              if (t.protocol !== "https:" || t.username || t.password || t.port && t.port !== "443" || !e.some((n) => t.hostname === n || t.hostname.endsWith(`.${n}`))) throw Object.assign(new Error("App \u7247\u6E90\u8FD4\u56DE\u4E86\u4E0D\u53D7\u652F\u6301\u7684\u670D\u52A1\u5730\u5740"), { code: "SECURITY_BLOCKED" });
              return t.href;
            }
            async function Pe(r, e, t) {
              let n = lt(r, ["fqnovel.com", "snssdk.com"]);
              for (let i = 0; i <= 3; i++) {
                if (globalThis.__hongguoCancelled) throw Object.assign(new Error("\u5DF2\u53D6\u6D88\u53D6\u6D41"), { code: "CANCELLED" });
                let o = Math.min(12e3, t - Date.now());
                if (o <= 0) throw Object.assign(new Error("App \u63A5\u53E3\u8D85\u65F6"), { code: "ETIMEDOUT" });
                let a = await fetch(n, { method: e.method || "GET", headers: e.headers, body: e.data ? S.from(e.data).toString("utf8") : void 0, redirect: "manual", timeoutMs: o });
                if ([301, 302, 303, 307, 308].includes(a.status)) {
                  let u = a.headers && (typeof a.headers.get == "function" ? a.headers.get("location") : a.headers.location);
                  if (e.method === "POST" || !u) throw Object.assign(new Error("App \u63A5\u53E3\u8DF3\u8F6C\u5F02\u5E38"), { code: "SECURITY_BLOCKED" });
                  n = lt(new dn(u, n).href, ["fqnovel.com", "snssdk.com"]);
                  continue;
                }
                if (a.status !== 200) throw Object.assign(new Error("App \u63A5\u53E3\u8BF7\u6C42\u5931\u8D25"), { code: "HTTP_" + a.status });
                let c = await a.text();
                if (!c || !c.trim()) throw Object.assign(new Error("App \u63A5\u53E3\u8FD4\u56DE\u7A7A\u6B63\u6587"), { code: "EMPTY_RESPONSE", category: "invalid_resp" });
                if (c.length > (/^https:\/\/reading\.snssdk\.com\/reading\/bookapi\/(search\/tab|bookmall\/(tab|cell\/change))\/v[?]/.test(n) || /^https:\/\/reading\.snssdk\.com\/novel\/player\/video_detail\/v1\/[?]/.test(n) ? 12 : 2) * 1024 * 1024) throw Object.assign(new Error("App \u63A5\u53E3\u54CD\u5E94\u65E0\u6548"), { code: "INVALID_RESPONSE" });
                let s = Lt(c);
                if (!s || typeof s != "object") throw Object.assign(new Error("App \u63A5\u53E3\u54CD\u5E94\u65E0\u6548"), { code: "INVALID_RESPONSE" });
                return s;
              }
              throw Object.assign(new Error("App \u63A5\u53E3\u8DF3\u8F6C\u8FC7\u591A"), { code: "SECURITY_BLOCKED" });
            }
            const appVideoModels = /* @__PURE__ */ new Map();
            let preferredAppModelRoute = null;
            let preferredAppModelUntil = 0;
            const appModelRoutes = [
              { url: xn, single: false },
              { url: "https://reading.snssdk.com/novel/player/multi_video_model/v1/", single: false },
              { url: "https://reading.snssdk.com/novel/player/video_model/v1/", single: true },
              { url: "https://api5-normal.fqnovel.com/novel/player/multi_video_model/v1/", single: false }
            ];
            function appModelExpiry(model, entry = {}) {
              const times = [entry.expire_time, model.__hongguoExpiresAt, model.url_expire].map((value) => {
                const number = Number(value);
                if (!Number.isSafeInteger(number) || number < 1e9) return 0;
                return number < 1e12 ? number * 1e3 : number;
              }).filter((value) => value > 0 && value <= 864e13);
              return times.length ? Math.min(...times) : 0;
            }
            async function requestAppVideoModel(videoId, device, deadline) {
              const preferred = preferredAppModelUntil > Date.now() ? preferredAppModelRoute : null;
              const routes = preferred ? [preferred, ...appModelRoutes.filter((route) => route !== preferred)] : appModelRoutes;
              let lastError;
              const biz = { detail_page_version: 0, device_level: 3, disable_digg_stat: false, need_all_video_definition: true, need_mp4_align: false, use_os_player: false, use_server_dns: false, video_platform: 1024 };
              for (const route of routes) {
                if (globalThis.__hongguoCancelled) throw Object.assign(new Error("\u64AD\u653E\u8BF7\u6C42\u5DF2\u53D6\u6D88"), { code: "CANCELLED" });
                if (Date.now() >= deadline) break;
                try {
                  const body = route.single ? { video_id: videoId, content_type: 1, biz_param: biz } : { biz_param: biz, mixed_video_id_map: { 1004: [videoId] } };
                  const signed = Ht(JSON.stringify(body), route.url, {}, device);
                  const response = await Pe(signed.url, { method: "POST", headers: signed.headers, data: signed.body }, Math.min(deadline, Date.now() + 3500));
                  if (Number(response.Code || response.code || 0) !== 0) throw Object.assign(new Error("\u5B98\u65B9\u63A5\u53E3\u6682\u672A\u63D0\u4F9B\u672C\u96C6\u64AD\u653E\u4FE1\u606F"), { code: "BUSINESS_REJECTED" });
                  if (!response.data || typeof response.data !== "object") throw Object.assign(new Error("\u5B98\u65B9\u64AD\u653E\u54CD\u5E94\u7F3A\u5C11\u6570\u636E"), { code: "INVALID_RESPONSE" });
                  const entry = route.single ? response.data : response.data[videoId];
                  const model = typeof (entry == null ? void 0 : entry.video_model) === "string" ? Lt(entry.video_model) : entry == null ? void 0 : entry.video_model;
                  if (!model) throw Object.assign(new Error("\u5B98\u65B9\u63A5\u53E3\u672A\u8FD4\u56DE\u6240\u9009\u5206\u96C6"), { code: (entry == null ? void 0 : entry.video_model) ? "INVALID_RESPONSE" : "MISSING_MODEL" });
                  model.__hongguoExpiresAt = appModelExpiry(model, entry);
                  preferredAppModelRoute = route;
                  preferredAppModelUntil = Date.now() + 5 * 60 * 1e3;
                  return model;
                } catch (error) {
                  lastError = error;
                  const recoverable = ["MISSING_MODEL", "EMPTY_RESPONSE", "RESPONSE_NOT_UTF8", "INVALID_RESPONSE", "HTTP_0", "HTTP_404", "HTTP_405", "HTTP_408", "HTTP_500", "HTTP_502", "HTTP_503", "HTTP_504", "ETIMEDOUT", "DNS", "TIMEOUT", "CONNECTION"].includes(error.code) || ["dns_error", "network_timeout", "conn_refused"].includes(error.category);
                  if (!recoverable || globalThis.__hongguoCancelled) throw error;
                  if (route === preferredAppModelRoute) {
                    preferredAppModelRoute = null;
                    preferredAppModelUntil = 0;
                  }
                }
              }
              throw Object.assign(lastError || new Error("\u5B98\u65B9\u64AD\u653E\u63A5\u53E3\u8BF7\u6C42\u8D85\u65F6"), { code: (lastError == null ? void 0 : lastError.code) || "ETIMEDOUT", routesExhausted: true });
            }
            async function oo(r, e = {}) {
              var _a;
              const t = Ri(e.quality);
              r = String(r || "");
              if (!/^\d{1,30}$/.test(r)) throw new Error("\u5206\u96C6\u7F16\u53F7\u65E0\u6548");
              const n = Math.min(Date.now() + 12e3, e.deadline || Infinity);
              const device = await Ot(n);
              const cacheKey = JSON.stringify([device.iid, device.device_id, device.cdid, r]);
              if (e.refreshModel) appVideoModels.delete(cacheKey);
              const cached = appVideoModels.get(cacheKey);
              const reusable = cached && cached.expiresAt > Date.now() + 5e3;
              const u = reusable ? cached.model : await requestAppVideoModel(r, device, n);
              let f = [], h;
              try {
                f = ln(u, r, t);
                if (f.length && !reusable) {
                  const expiresAt = Math.min(appModelExpiry(u) || Date.now() + 3e4, Date.now() + 3e5);
                  if (expiresAt > Date.now() + 5e3) {
                    if (!appModelExpiry(u)) u.__hongguoExpiresAt = expiresAt;
                    appVideoModels.delete(cacheKey);
                    appVideoModels.set(cacheKey, { model: u, expiresAt });
                    while (appVideoModels.size > 8) appVideoModels.delete(appVideoModels.keys().next().value);
                    f = ln(u, r, t);
                  }
                }
              } catch (error) {
                h = error;
              }
              if (f.length && !e.includeFallback) return { ...f[0], variants: f };
              let d = ro(u.fallback_api);
              if (d && (!f.length || e.includeFallback || !Object.keys(u.video_list || {}).length || u.dynamic_video)) {
                d = lt(d, ["fqnovel.com", "snssdk.com"]);
                d = d.replace(/([?&])force_fids=[^&]*(&?)/, (y, I, F) => F ? I : "");
                d = /[?&]format_type=/.test(d) ? d.replace(/([?&]format_type=)[^&]*/, "$1mp4") : d + (d.includes("?") ? "&" : "?") + "format_type=mp4";
                d = /[?&]codec_type=/.test(d) ? d.replace(/([?&]codec_type=)[^&]*/, "$11") : d + (d.includes("?") ? "&" : "?") + "codec_type=1";
                try {
                  let y = await Pe(d, { headers: { "User-Agent": dt } }, n);
                  if ([y, y.video_info].some((F) => Number((F == null ? void 0 : F.Code) || (F == null ? void 0 : F.code) || 0) !== 0)) {
                    throw Object.assign(new Error("App \u63A5\u53E3\u6682\u672A\u63D0\u4F9B\u672C\u96C6\u64AD\u653E\u4FE1\u606F"), { code: "BUSINESS_REJECTED" });
                  }
                  let I = (_a = y == null ? void 0 : y.video_info) == null ? void 0 : _a.data;
                  if (!I) throw Object.assign(new Error("App \u63A5\u53E3\u672A\u8FD4\u56DE\u672C\u96C6\u7247\u6E90\u6A21\u578B"), { code: "MISSING_MODEL" });
                  f.push(...ln(I, r, t));
                } catch (y) {
                  h = y;
                }
              }
              let x = /* @__PURE__ */ new Set();
              if (f = f.filter((y) => {
                let I = y.url + ":" + (y.contentKey || "");
                return x.has(I) ? false : (x.add(I), true);
              }), f.length) return { ...f[0], variants: f };
              throw h || Object.assign(new Error("App \u63A5\u53E3\u672A\u8FD4\u56DE\u672C\u96C6\u7247\u6E90\u5730\u5740"), { code: "MISSING_MODEL" });
            }
            function ln(model, videoId, downloadQuality) {
              var _a, _b;
              const entries = Object.values((model == null ? void 0 : model.video_list) || {}).filter((item) => item && (item.main_url || item.backup_url || Array.isArray(item.backup_url_list))).map((item) => {
                var _a2;
                const meta = item.video_meta || {};
                const codec = fe(item.codec_type || meta.codec_type).toLowerCase();
                const codecRank = ["h264", "avc", "avc1"].includes(codec) ? 0 : ["hevc", "h265", "hvc1", "hev1", "bytevc1"].includes(codec) ? 1 : !codec && ["mp4", "mpeg"].includes(fe(item.vtype).toLowerCase()) ? 2 : 3;
                const [width, height] = [[item.vwidth, item.vheight], [item.width, item.height], [meta.vwidth, meta.vheight], [meta.width, meta.height]].map((pair) => pair.map(Number)).find((pair) => pair.every((value) => Number.isFinite(value) && value > 0)) || [0, 0];
                const label = fe(item.quality_desc || item.definition || meta.definition);
                const pixels = width > 0 && height > 0 ? Math.min(width, height) : Number(((_a2 = label.match(/\d+/)) == null ? void 0 : _a2[0]) || 0);
                return { item, codec, codecRank, pixels, quality: pixels > 0 ? pixels + "p" : "", width, height };
              }).filter((value) => value.codecRank < 3 && Di(value, downloadQuality)).sort((left, right) => downloadQuality === "auto" ? right.pixels - left.pixels || left.codecRank - right.codecRank : Math.min(left.width, left.height) - Math.min(right.width, right.height) || left.codecRank - right.codecRank);
              if (!entries.length) throw new Error(downloadQuality === "auto" ? "\u672C\u96C6\u6682\u672A\u63D0\u4F9B\u517C\u5BB9\u7684 H.264/HEVC \u7247\u6E90" : "\u672C\u96C6\u6682\u672A\u63D0\u4F9B\u6EE1\u8DB3\u4E0B\u8F7D\u6E05\u6670\u5EA6\u7684\u7247\u6E90");
              const r = model, e = videoId, t = downloadQuality, n = entries;
              let i, o = [], a = /* @__PURE__ */ new Set();
              for (let c of n) try {
                let s = c.item.spade_a || ((_a = c.item.encrypt_info) == null ? void 0 : _a.spade_a), u = s ? no(s) : null;
                for (let f of [c.item.main_url, c.item.backup_url, c.item.backup_url_1, c.item.backup_url_2, c.item.backup_url_3, ...Array.isArray(c.item.backup_url_list) ? c.item.backup_url_list : []]) if (!(typeof f != "string" || !f)) try {
                  let h = r.key_seed ? io(f, S.from(r.key_seed, "base64")) : /^https:\/\//i.test(cn(f)) ? cn(f) : S.from(f, "base64").toString("utf8"), d = lt(h, ["qznovelvod.com", "fqnovelvod.com", "douyinvod.com"]), x = u ? u.toString("hex") : null, y = `${d}:${x || ""}`;
                  if (a.has(y)) continue;
                  a.add(y), o.push({ url: d, contentKey: x, codec: c.codec === "bytevc1" ? "hevc" : c.codec || "auto", source: "app", vid: e, expiresAt: appModelExpiry(r), userAgent: dt, referer: "https://novelquickapp.com/", mediaBytes: Math.max(0, Number(c.item.size || ((_b = c.item.video_meta) == null ? void 0 : _b.size) || 0)), quality: c.quality, width: c.width, height: c.height });
                } catch (h) {
                  i = h;
                }
              } catch (s) {
                i = s;
              }
              if (o.length) return o;
              throw (i == null ? void 0 : i.code) === "SECURITY_BLOCKED" ? i : Object.assign(new Error("\u672C\u96C6\u7247\u6E90\u5730\u5740\u6216\u5BC6\u94A5\u65E0\u6CD5\u89E3\u6790"), { code: "INVALID_RESPONSE" });
            }
            var he = { ...yn, version_code: "73932", version_name: "7.3.9.32", manifest_version_code: "73932", update_version_code: "73932", pv_player: "73932" }, Ae;
            function ao() {
              let r = K.randomBytes(16);
              r[6] = r[6] & 15 | 64, r[8] = r[8] & 63 | 128;
              let e = r.toString("hex");
              return [e.slice(0, 8), e.slice(8, 12), e.slice(12, 16), e.slice(16, 20), e.slice(20)].join("-");
            }
            async function Ot(r = 1 / 0) {
              if (globalThis.__hongguoCachedDevice && /^\d{10,24}$/.test(fe(globalThis.__hongguoCachedDevice.iid)) && /^\d{10,24}$/.test(fe(globalThis.__hongguoCachedDevice.device_id))) {
                globalThis.__hongguoCachedDevice = { ...globalThis.__hongguoCachedDevice, ...he, iid: fe(globalThis.__hongguoCachedDevice.iid), device_id: fe(globalThis.__hongguoCachedDevice.device_id), cdid: fe(globalThis.__hongguoCachedDevice.cdid) || ao() };
                return globalThis.__hongguoCachedDevice;
              }
              return Ae || (Ae = (async () => {
                let e = ao(), t = { aid: 8662, app_name: "novelread", package: "com.phoenix.read", app_version: he.version_name, version_code: 73932, update_version_code: 73932, manifest_version_code: 73932, sdk_version: "6.18.0", device_platform: "android", os: "Android", os_version: he.os_version, os_api: Number(he.os_api), device_model: he.device_type, device_brand: he.device_brand, device_manufacturer: "Xiaomi", density_dpi: Number(he.dpi), display_density: "mdpi", resolution: he.resolution.replace("*", "x"), language: "zh", timezone: 8, access: "wifi", channel: he.channel, cdid: e, openudid: K.randomBytes(8).toString("hex") }, n = await Pe("https://log.snssdk.com/service/2/device_register/?aid=8662&app_name=novelread", { method: "POST", headers: { "Content-Type": "application/json; charset=utf-8", "User-Agent": dt }, data: JSON.stringify({ magic_tag: "ss_app_log", header: t, _gen_time: Date.now() }) }, Math.min(Date.now() + 12e3, r)), i = fe(n.install_id_str), o = fe(n.device_id_str);
                if (!/^\d{10,24}$/.test(i) || !/^\d{10,24}$/.test(o)) throw Object.assign(new Error("\u65E0\u6CD5\u521D\u59CB\u5316\u5B98\u65B9\u4F1A\u8BDD"), { code: "GUEST_REGISTRATION_FAILED" });
                let dev = { ...he, iid: i, device_id: o, cdid: e };
                globalThis.__hongguoCachedDevice = dev;
                if (typeof __native_save_device === "function") {
                  try {
                    __native_save_device(JSON.stringify(dev));
                  } catch (_) {
                  }
                }
                return dev;
              })().catch((e) => {
                throw Ae = null, e;
              })), Ae;
            }
            async function co(r, e = {}, t = false) {
              t && !globalThis.__hongguoAccountActive && (Ae = null, delete globalThis.__hongguoCachedDevice);
              let deadline = Math.min(Date.now() + 12e3, e.deadline || 1 / 0), n = await Ot(deadline), i = { query: r, count: 0, offset: e.offset || 0, tab_type: e.fallbackToGeneral ? 11 : 29, tab_name: e.fallbackToGeneral ? "" : "feed", search_source: 1, use_correct: false, use_lynx: false, user_is_login: globalThis.__hongguoAccountActive ? 1 : 0, bookshelf_search_plan: 4, bookstore_tab: 16, is_first_enter_search: !e.offset };
              e.passback && (i.passback = e.passback), e.searchId && (i.search_id = e.searchId);
              let o = Ht(null, "https://reading.snssdk.com/reading/bookapi/search/tab/v", i, n), a = await Pe(o.url, { headers: { ...o.headers, lc: "101" } }, deadline);
              if (Number(a.code) !== 0 || !Array.isArray(a.search_tabs)) throw Object.assign(new Error("\u5B98\u65B9\u641C\u7D22\u672A\u8FD4\u56DE\u6709\u6548\u7ED3\u679C"), { code: "SEARCH_REJECTED", category: "business_reject" });
              return a;
            }
            async function so({ seriesId: r, videoId: e, startMs: t = 0, durationMs: n, cursor: i = "" }) {
              if (!/^\d{10,30}$/.test(String(r)) || !/^\d{10,30}$/.test(String(e))) throw new Error("\u5F39\u5E55\u5206\u96C6\u7F16\u53F7\u65E0\u6548");
              let o = { comment_source: 601, server_channel: 1e3, group_id: String(e), group_type: 30, comment_type: 20, sort: 1, business_param: { book_id: String(r), start_offset_time: t, playlet_item_duration: n }, count: 90, cursor: String(i), aid: 8662, compliance_status: 0 }, a = await Ot(), c = Ht(JSON.stringify(o), "https://reading.snssdk.com/novel/commentapi/comment/list/" + e + "/v1/", {}, a);
              return Pe(c.url, { method: "POST", headers: { ...c.headers, lc: "101" }, data: c.body }, Date.now() + 5e3);
            }
            mn.exports = { buildAccountRequest: async function(action = "profile", payload = {}) {
              const routes = { profile: "/reading/user/info/v1/", favorites: "/reading/bookapi/bookshelf/video/list/v1/", history: "/reading/bookapi/read_progress/list/v1/", libraryDetails: "/reading/bookapi/multi-detail/v1/", libraryDetail: "/novel/player/video_detail/v1/", favoriteUpdate: "/reading/bookapi/bookshelf/video/update/v1/", progressGet: "/reading/bookapi/read_progress/get/v1/", progressUpdate: "/reading/bookapi/read_progress/upload/v1/", socialDetail: "/novel/player/video_detail/v1/", creatorList: "/reading/user/celebrity/list/v1/", likeUpdate: "/reading/ugc/action/set/v1/", creatorFollow: "/novel/commentapi/comment/do_action/v1/", followingCreators: "/novel/commentapi/relation/list/", creatorWorks: "/novel/commentapi/user/profile/", likedVideos: "/reading/ugc/action/mget/v", creatorProfile: "/reading/user/profile/get/v", commentList: "/novel/commentapi/comment/list/", commentReplyList: "/novel/commentapi/reply/list/" };
              if (!Object.prototype.hasOwnProperty.call(routes, action)) throw new Error("\u4E0D\u652F\u6301\u7684\u8D26\u53F7\u64CD\u4F5C");
              const identity = (value) => {
                const id = String(value || "");
                if (!/^[1-9]\d{0,29}$/.test(id)) throw new Error("\u8D26\u53F7\u5267\u96C6\u7F16\u53F7\u65E0\u6548");
                return id;
              };
              const integer = (value) => {
                const n = Number(value);
                if (!Number.isSafeInteger(n) || n < 0) throw new Error("\u8D26\u53F7\u8FDB\u5EA6\u53C2\u6570\u65E0\u6548");
                return n;
              };
              const params = action === "history" ? { book_types: "2", limit: "50" } : {};
              let body = null;
              if (action === "libraryDetails") {
                const ids = String(payload.ids || "").split(",");
                if (!ids.length || ids.length > 50) throw new Error("\u8D26\u53F7\u5267\u96C6\u7F16\u53F7\u65E0\u6548");
                params.book_id = ids.map(identity).join(",");
                params.book_type = "2";
              }
              if (action === "favorites") params.target_user_id = identity(payload.userId);
              if (action === "favoriteUpdate") {
                if (!["0", "1"].includes(String(payload.follow))) throw new Error("\u8FFD\u5267\u72B6\u6001\u65E0\u6548");
                const add = String(payload.follow) === "1";
                const row = { book_id: identity(payload.id), book_type: 2, modify_time: Date.now(), video_shelf_operate_type: add ? 0 : 1 };
                if (!add) row.group_name = "";
                body = { is_cancelled: false, update_bookshelf_video_list: [row] };
              }
              if (action === "progressGet") body = { book_ids: { "2": [identity(payload.id)] } };
              if (action === "progressUpdate") {
                const duration = integer(payload.durationMs), position = Math.min(integer(payload.positionMs), duration), episode = integer(payload.episode), count = integer(payload.episodes);
                if (!duration || !episode || count && episode > count) throw new Error("\u8D26\u53F7\u8FDB\u5EA6\u53C2\u6570\u65E0\u6548");
                body = { books: [{ book_id: identity(payload.id), item_id: identity(payload.itemId), vid_index: episode, current_play_time: position, current_total_time: duration, episode_count: count, read_timestamp_ms: integer(payload.updatedAt), book_type: 2, progress_rate: String(position / duration) }], write_mode: 1 };
              }
              if (action === "socialDetail" || action === "libraryDetail") body = { series_id: identity(payload.id) };
              if (action === "creatorList") Object.assign(params, { series_id: identity(payload.id), list_type: 3, count: 50, offset: 0 });
              if (action === "followingCreators") {
                const count = integer(payload.count === void 0 ? 20 : payload.count);
                if (count < 1 || count > 50) throw new Error("\u8D26\u53F7\u5217\u8868\u5206\u9875\u5927\u5C0F\u65E0\u6548");
                const offset = integer(payload.offset === void 0 ? 0 : payload.offset);
                const uid = identity(payload.userId);
                const cursor = payload.cursor !== void 0 && payload.cursor !== null && String(payload.cursor) !== "" ? String(payload.cursor) : offset > 0 ? String(offset) : "";
                body = { aid: integer(he.aid), comment_source: 1507, count, cursor, target_user_id: uid };
              }
              if (action === "creatorWorks") {
                const count = integer(payload.count === void 0 ? 20 : payload.count);
                if (count < 1 || count > 50) throw new Error("\u8D26\u53F7\u5217\u8868\u5206\u9875\u5927\u5C0F\u65E0\u6548");
                const offset = integer(payload.offset === void 0 ? 0 : payload.offset);
                const uid = identity(payload.userId);
                const cursor = payload.cursor !== void 0 && payload.cursor !== null && String(payload.cursor) !== "" ? String(payload.cursor) : offset > 0 ? String(offset) : "";
                const commentSource = payload.commentSource !== void 0 && payload.commentSource !== null && String(payload.commentSource) !== "" ? integer(payload.commentSource) : 1506;
                const tabType = payload.tabType !== void 0 && payload.tabType !== null && String(payload.tabType) !== "" ? integer(payload.tabType) : 23;
                body = { aid: integer(he.aid), comment_source: commentSource, tab_type: tabType, count, cursor, target_user_id: uid };
              }
              if (action === "likedVideos") {
                const count = integer(payload.count === void 0 ? 20 : payload.count);
                if (count < 1 || count > 50) throw new Error("\u8D26\u53F7\u5217\u8868\u5206\u9875\u5927\u5C0F\u65E0\u6548");
                Object.assign(params, { count, offset: integer(payload.offset === void 0 ? 0 : payload.offset), object_type_list: "6,15,10", action_type: 3 });
              }
              if (action === "creatorProfile") params.user_id = identity(payload.userId);
              if (action === "likeUpdate") {
                if (!["0", "1"].includes(String(payload.like))) throw new Error("\u70B9\u8D5E\u72B6\u6001\u65E0\u6548");
                body = { object_id: identity(payload.itemId), object_type: 6, action_type: String(payload.like) === "1" ? 3 : 4, action_category: 1 };
              }
              if (action === "creatorFollow") {
                const type = integer(payload.relativeType);
                if (![2, 3].includes(type) || !["0", "1"].includes(String(payload.follow))) throw new Error("\u5173\u6CE8\u53C2\u6570\u65E0\u6548");
                body = { object_id: identity(payload.userId), object_type: 1, action_type: String(payload.follow) === "1" ? 25 : 26, aid: integer(he.aid), business_param: { shark_param: {} } };
              }
              if (action === "commentList") {
                const count = integer(payload.count === void 0 ? 20 : payload.count);
                if (count < 1 || count > 50) throw new Error("\u8D26\u53F7\u5217\u8868\u5206\u9875\u5927\u5C0F\u65E0\u6548");
                const bookId = identity(payload.bookId || payload.id);
                const cursor = payload.cursor !== void 0 && payload.cursor !== null && String(payload.cursor) !== "" ? String(payload.cursor) : "";
                const sort = integer(payload.sort === void 0 ? 1 : payload.sort);
                body = { aid: integer(he.aid), comment_source: 1, server_channel: 34, group_id: bookId, group_type: 1, comment_type: 2, sort, count, cursor, compliance_status: 0, business_param: { book_id: bookId } };
              }
              if (action === "commentReplyList") {
                const count = integer(payload.count === void 0 ? 20 : payload.count);
                if (count < 1 || count > 50) throw new Error("\u8D26\u53F7\u5217\u8868\u5206\u9875\u5927\u5C0F\u65E0\u6548");
                const commentId = identity(payload.commentId);
                const bookId = payload.bookId || payload.id ? identity(payload.bookId || payload.id) : "";
                const cursor = payload.cursor !== void 0 && payload.cursor !== null && String(payload.cursor) !== "" ? String(payload.cursor) : "";
                const commentSource = payload.commentSource !== void 0 ? integer(payload.commentSource) : 1011;
                const serverChannel = payload.serverChannel !== void 0 ? integer(payload.serverChannel) : 34;
                body = { aid: integer(he.aid), comment_id: commentId, comment_source: commentSource, server_channel: serverChannel, group_id: bookId, group_type: 1, comment_type: 2, count, cursor, compliance_status: 0, business_param: { book_id: bookId, real_level: 2 } };
              }
              let dev;
              if (action === "profile" && payload.device) {
                let bound;
                try {
                  bound = JSON.parse(payload.device);
                } catch (_) {
                  throw new Error("\u8D26\u53F7\u8BBE\u5907\u4E0A\u4E0B\u6587\u65E0\u6548");
                }
                if (!bound || !/^\d{10,24}$/.test(String(bound.iid || "")) || !/^\d{10,24}$/.test(String(bound.device_id || "")) || typeof bound.cdid !== "string" || bound.cdid.length > 80) throw new Error("\u8D26\u53F7\u8BBE\u5907\u4E0A\u4E0B\u6587\u65E0\u6548");
                dev = { ...he, iid: String(bound.iid), device_id: String(bound.device_id), cdid: bound.cdid };
              } else dev = await Ot();
              const wireBody = body === null ? null : action === "progressGet" ? '{"book_ids":{"2":[' + identity(payload.id) + "]}}" : JSON.stringify(body);
              const origin = ["followingCreators", "creatorWorks", "likedVideos", "creatorProfile", "commentList", "commentReplyList"].includes(action) ? "https://reading.snssdk.com" : "https://api5-normal-sinfonlinea.fqnovel.com";
              const path = action === "followingCreators" || action === "creatorWorks" ? routes[action] + identity(payload.userId) + "/v1/" : action === "commentList" ? routes[action] + identity(payload.bookId || payload.id) + "/v1/" : action === "commentReplyList" ? routes[action] + identity(payload.commentId) + "/v1/" : routes[action];
              const signed = Ht(wireBody, origin + path, params, dev);
              return { url: signed.url, method: body === null ? "GET" : "POST", headers: signed.headers, ...body === null ? {} : { body: wireBody } };
            }, resetGuestSession: function() {
              Ae = null;
              appVideoModels.clear();
              delete globalThis.__hongguoCachedDevice;
            }, fetchAppDetailRaw: async function(id) {
              var _a;
              const dev = await Ot();
              const signed = Ht(JSON.stringify({ series_id: String(id) }), "https://reading.snssdk.com/novel/player/video_detail/v1/", {}, dev);
              const result = await Pe(signed.url, { method: "POST", headers: { ...signed.headers, lc: "101" }, data: signed.body }, Date.now() + 12e3);
              if (Number(result.code || 0) !== 0) throw Object.assign(new Error("\u5B98\u65B9\u8BE6\u60C5\u63A5\u53E3\u6682\u4E0D\u53EF\u7528\uFF0C\u8BF7\u91CD\u8BD5"), { code: "DETAIL_REJECTED" });
              return (_a = result.data) == null ? void 0 : _a.video_data;
            }, fetchAppPlayUrl: oo, fetchAppSearchRaw: co, fetchAppDanmakuRaw: so, fetchAppDiscoveryRaw: async function(path, params) {
              var _a;
              if (!["/reading/bookapi/search/cue/v", "/reading/bookapi/search/suggest/v", "/reading/bookapi/plan/v", "/reading/bookapi/bookmall/tab/v", "/reading/bookapi/bookmall/cell/change/v"].includes(path)) throw Object.assign(new Error("\u4E0D\u652F\u6301\u7684\u5B98\u65B9\u63A5\u53E3"), { code: "SECURITY_BLOCKED" });
              const device = await Ot();
              const signed = Ht(null, "https://reading.snssdk.com" + path, params, device);
              const result = await Pe(signed.url, { headers: { ...signed.headers, lc: "101" } }, Date.now() + 12e3);
              if (!result || String((_a = result.code) != null ? _a : result.status_code) !== "0") throw Object.assign(new Error("\u5B98\u65B9\u53D1\u73B0\u63A5\u53E3\u6682\u4E0D\u53EF\u7528\uFF0C\u8BF7\u91CD\u8BD5"), { code: "DISCOVERY_REJECTED" });
              return result;
            } };
          });
          var wn = z((Do, vn) => {
            var { fetchAppSearchRaw: bn } = pt();
            function fo(r) {
              let e = [], t = /* @__PURE__ */ new Set();
              let tabs = Array.isArray(r) ? r : r ? [r] : [];
              for (let m of tabs) {
                for (let n of m.data || []) {
                  let i = Array.isArray(n.video_data) ? n.video_data : [];
                  for (let o of i) {
                    let a = o.video_detail || {}, c = String(a.series_id_str || o.series_id || a.series_id || "");
                    if (!/^\d{10,30}$/.test(c) || t.has(c)) continue;
                    let s = String(a.series_title || o.title || "").trim();
                    if (!s) continue;
                    t.add(c);
                    let u = Number(a.episode_cnt || o.episode_cnt || 0);
                    e.push({ vod_id: c, vod_name: s, vod_pic: cleanCoverUrl(String(a.series_cover || o.cover || "")), vod_remarks: u > 0 ? "\u5168" + u + "\u96C6" : "", vod_content: String(a.series_intro || ""), vod_total: u, content_type: Number(a.content_type || o.content_type || 0) });
                  }
                }
              }
              return e;
            }
            function pickTab(response, general) {
              const tabs = response.search_tabs || [];
              const type = general ? 11 : 29;
              return tabs.find((tab) => Number(tab.tab_type) === type) || tabs.find((tab) => general ? tab.title === "\u7EFC\u5408" : ["\u5267\u96C6", "\u77ED\u5267"].includes(tab.title)) || (general ? tabs.find((tab) => fo(tab).length > 0) : void 0);
            }
            function toPage(response, tab, offset, general) {
              const list = fo(tab);
              const next = Number((tab == null ? void 0 : tab.next_offset) || 0);
              const more = (tab == null ? void 0 : tab.has_more) === true;
              if (more && (!Number.isSafeInteger(next) || next <= offset)) {
                throw Object.assign(new Error("\u5B98\u65B9\u641C\u7D22\u6E38\u6807\u672A\u63A8\u8FDB\uFF0C\u8BF7\u91CD\u65B0\u641C\u7D22"), { code: "INVALID_SEARCH_CURSOR" });
              }
              return { list, hasMore: more, cursor: {
                offset: next,
                passback: String((tab == null ? void 0 : tab.passback) || ""),
                searchId: String((tab == null ? void 0 : tab.search_id) || ""),
                fallbackToGeneral: general
              } };
            }
            async function uo(query, cursor = {}) {
              const deadline = Date.now() + 45e3;
              async function request(value) {
                value = { ...value, deadline };
                try {
                  return await bn(query, value);
                } catch (error) {
                  if (globalThis.__hongguoCancelled) throw error;
                  const renew = ["INVALID_RESPONSE", "SEARCH_REJECTED"].includes(error.code);
                  const transient = ["HTTP_0", "HTTP_408", "HTTP_500", "HTTP_502", "HTTP_503", "HTTP_504", "ETIMEDOUT", "EMPTY_RESPONSE"].includes(error.code) || ["dns_error", "network_timeout", "conn_refused"].includes(error.category);
                  if (!renew && !transient) throw error;
                  return await bn(query, value, renew);
                }
              }
              const response = await request(cursor);
              const offset = Number(cursor.offset || 0);
              const general = cursor.fallbackToGeneral === true;
              const tab = pickTab(response, general);
              const result = toPage(response, tab, offset, general);
              if (general || offset || result.list.length || globalThis.__hongguoCancelled) {
                if (!tab) throw Object.assign(new Error("\u5B98\u65B9\u641C\u7D22\u672A\u8FD4\u56DE\u77ED\u5267\u6570\u636E\u5206\u7C7B\uFF0C\u8BF7\u5BFC\u51FA\u8BCA\u65AD\u62A5\u544A"), { code: "SEARCH_TAB_MISSING" });
                return result;
              }
              const fallback = await request({ fallbackToGeneral: true });
              const fallbackTab = pickTab(fallback, true);
              const fallbackResult = toPage(fallback, fallbackTab, 0, true);
              if (fallbackResult.list.length) return fallbackResult;
              if (!tab) throw Object.assign(new Error("\u5B98\u65B9\u641C\u7D22\u672A\u8FD4\u56DE\u77ED\u5267\u6570\u636E\u5206\u7C7B\uFF0C\u8BF7\u5BFC\u51FA\u8BCA\u65AD\u62A5\u544A"), { code: "SEARCH_TAB_MISSING" });
              return result;
            }
            vn.exports = { fetchAppSearchPage: uo };
          });
          var En = z((No, _n) => {
            var { fetchAppDanmakuRaw: ho } = pt();
            async function lo(r, e, t) {
              var _a, _b, _c, _d, _e;
              let n = /^hongguo:(\d{10,30}):(\d{10,30})$/.exec(String(r));
              if (!n || !Number.isSafeInteger(e) || !Number.isSafeInteger(t) || e < 0 || e >= t || t > 864e5) throw new Error("\u5F39\u5E55\u5206\u96C6\u6216\u65F6\u95F4\u8303\u56F4\u65E0\u6548");
              let i = Math.min(e + 3e4, t), o = await ho({ seriesId: n[1], videoId: n[2], startMs: e, durationMs: t });
              if (Number(o.code) !== 0 || !Array.isArray((_a = o.data) == null ? void 0 : _a.data_list)) throw new Error("\u5B98\u65B9\u5F39\u5E55\u6682\u4E0D\u53EF\u7528");
              let a = String(((_b = o.data.common_list_info) == null ? void 0 : _b.cursor) || "");
              if (a) {
                let u;
                try {
                  u = JSON.parse(a);
                } catch (e2) {
                }
                if (u && Number(u.start_offset_time) !== e) throw new Error("\u5B98\u65B9\u5F39\u5E55\u65F6\u95F4\u8303\u56F4\u4E0D\u7B26");
              }
              let c = /* @__PURE__ */ new Set(), s = [];
              for (let u of o.data.data_list) {
                let f = u == null ? void 0 : u.comment;
                if (String(((_c = f == null ? void 0 : f.common) == null ? void 0 : _c.group_id) || "") !== n[2]) continue;
                let h = String(f.comment_id || ""), d = Number((_d = f.expand) == null ? void 0 : _d.offset_time), x = (_e = f.common.content) == null ? void 0 : _e.text;
                if (!h || h.length > 120 || c.has(h) || !Number.isSafeInteger(d) || d < e || d >= i || typeof x != "string") continue;
                let y = Array.from(x.replace(/[\x00-\x1f\x7f-\x9f\u2028\u2029]/g, " ").trim()).slice(0, 180).join("");
                if (y && (c.add(h), s.push({ id: h, timeMs: d, text: y, color: "#FFFFFF" }), s.length >= 90)) break;
              }
              return s.sort((u, f) => u.timeMs - f.timeMs), { episodeId: r, startMs: e, nextMs: i, items: s };
            }
            _n.exports = { fetchAppDanmakuPage: lo };
          });
          var go = z((To, Bn) => {
            var { fetchAppPlayUrl: po } = pt(), { fetchAppSearchPage: xo } = wn(), { fetchAppDanmakuPage: yo } = En();
            Bn.exports = { buildAccountRequest: pt().buildAccountRequest, resetGuestSession: pt().resetGuestSession, fetchAppDetailRaw: pt().fetchAppDetailRaw, fetchAppPlayUrl: po, fetchAppSearchPage: xo, fetchAppDanmakuPage: yo, fetchAppDiscoveryRaw: pt().fetchAppDiscoveryRaw };
          });
          return go();
        })();
        return globalThis.__hongguoLocalSign;
      })();
      delete globalThis.__hongguoLocalSign;
      delete globalThis.__hongguoHasBuiltInSigning;
      delete globalThis.__hongguoUseLocalApkProfile;
      if (typeof portableSign !== "function") {
        throw new Error("\u4FBF\u643A\u7B7E\u540D\u5668\u521D\u59CB\u5316\u5931\u8D25\uFF1A\u672A\u53D6\u5230\u7B7E\u540D\u5165\u53E3");
      }
      function sign(url, body, epoch, device) {
        return portableSign(url, body, epoch, device || {});
      }
      module.exports = { sign };
    }
  });

  // ../hgw/server/src/core/pure-sign.js
  var require_pure_sign = __commonJS({
    "../hgw/server/src/core/pure-sign.js"(exports, module) {
      "use strict";
      var crypto = require_shim_crypto();
      var Crypto = require_crypto();
      var ThlSign = require_thl_sign();
      if (!crypto.getHashes().includes("sm3")) {
        throw new Error("\u5F53\u524D Node \u8FD0\u884C\u65F6\u7F3A\u5C11 SM3 \u7B97\u6CD5\u652F\u6301\uFF08\u9700 OpenSSL >= 1.1.1\uFF09\uFF0Cx-medusa \u7B7E\u540D\u94FE\u8DEF\u65E0\u6CD5\u5DE5\u4F5C");
      }
      function rotl(x, n) {
        const k = n & 31;
        return x << k | x >>> (32 - k & 31) | 0;
      }
      function ror(x, n) {
        const k = n & 31;
        return x >>> k | x << (32 - k & 31) | 0;
      }
      function rotl8(x) {
        return (x << 4 | x >>> 4) & 255;
      }
      function rotl8_3(x) {
        return (x << 3 | x >>> 5) & 255;
      }
      function reverseBits(value) {
        let r = 0;
        for (let i = 0; i < 8; i++) r = r << 1 | value >> i & 1;
        return r;
      }
      function readLe32(b, off) {
        return b.readInt32LE(off);
      }
      function readBe32(b, off) {
        return b.readInt32BE(off);
      }
      function putLe32(b, off, v) {
        b.writeInt32LE(v | 0, off);
      }
      function putBe32(b, off, v) {
        b.writeInt32BE(v | 0, off);
      }
      function le32(v) {
        const b = Buffer.alloc(4);
        b.writeInt32LE(v | 0, 0);
        return b;
      }
      function be32(v) {
        const b = Buffer.alloc(4);
        b.writeInt32BE(v | 0, 0);
        return b;
      }
      function readU64Le(b, off) {
        return b.readBigUInt64LE(off);
      }
      function putU64Le(b, off, v) {
        b.writeBigUInt64LE(BigInt.asUintN(64, BigInt(v)), off);
      }
      function rotr64(x, n) {
        const v = BigInt.asUintN(64, x);
        const k = BigInt(n & 63);
        if (k === /* @__PURE__ */ BigInt("0")) return v;
        return BigInt.asUintN(64, v >> k | v << /* @__PURE__ */ BigInt("64") - k);
      }
      function xorBytes(a, b) {
        const out = Buffer.from(a);
        for (let i = 0; i < out.length; i++) out[i] = out[i] ^ b[i % b.length];
        return out;
      }
      function md5(data) {
        return Crypto.md5(data);
      }
      function sm3(data) {
        return crypto.createHash("sm3").update(data).digest();
      }
      var EMPTY = Buffer.alloc(0);
      function varint(value) {
        let n = typeof value === "bigint" ? value : BigInt(value);
        const out = [];
        while (n > /* @__PURE__ */ BigInt("127")) {
          out.push(Number(n & /* @__PURE__ */ BigInt("127") | /* @__PURE__ */ BigInt("128")));
          n >>= /* @__PURE__ */ BigInt("7");
        }
        out.push(Number(n));
        return Buffer.from(out);
      }
      function zigzag(value) {
        return value < /* @__PURE__ */ BigInt("0") ? -value * /* @__PURE__ */ BigInt("2") - /* @__PURE__ */ BigInt("1") : value * /* @__PURE__ */ BigInt("2");
      }
      function protoField(tag, value, type) {
        if (value === null || value === void 0) return EMPTY;
        if (type === "string" && value === "") return EMPTY;
        let head;
        let body;
        if (type === "bytes" || type === "message") {
          body = value;
          head = Buffer.concat([varint(BigInt(tag) << /* @__PURE__ */ BigInt("3") | /* @__PURE__ */ BigInt("2")), varint(body.length)]);
        } else if (type === "string") {
          body = Buffer.from(String(value));
          head = Buffer.concat([varint(BigInt(tag) << /* @__PURE__ */ BigInt("3") | /* @__PURE__ */ BigInt("2")), varint(body.length)]);
        } else if (type === "float") {
          body = Buffer.alloc(4);
          body.writeFloatLE(Number(value), 0);
          head = varint(BigInt(tag) << /* @__PURE__ */ BigInt("3") | /* @__PURE__ */ BigInt("5"));
        } else {
          const v = BigInt(Math.trunc(Number(value)));
          head = varint(BigInt(tag) << /* @__PURE__ */ BigInt("3"));
          body = varint(type === "sint" ? zigzag(v) : v);
        }
        return Buffer.concat([head, body]);
      }
      function proto(fields) {
        const parts = [];
        for (const f of fields) {
          const type = f.length > 2 ? String(f[2]) : "string";
          parts.push(protoField(Number(f[0]), f[1], type));
        }
        return Buffer.concat(parts);
      }
      function getIv(iv, data) {
        let value = iv;
        for (let i = 0; i < data.length; i++) {
          const d = data[i] & 255;
          if ((i & 1) === 0) {
            value = value >>> 4 ^ value ^ value << 6 ^ d | 0;
          } else {
            value = ~(value >>> 7 ^ value ^ (d | value << 12));
          }
        }
        return value;
      }
      function sumMd5(data) {
        let check = 539100192;
        for (let i = 0; i < 12; i++) {
          const temp = (i & 1) === 0 ? check >>> 3 ^ check : check >>> 5 ^ check;
          check = (i & 1) === 0 ? data[i] & 255 ^ check << 7 : data[i] & 255 | check << 11;
          if ((i & 1) !== 0) check = ~check;
          check = check ^ temp;
        }
        return (check | 4) ^ 16777216 | 0;
      }
      var BRANCH2_SV = [
        2813263392,
        1900671446,
        1206176263,
        3920990055,
        2478384350,
        3323252981,
        951050479,
        2998644083,
        3796124867,
        2637884571,
        3749394404,
        3635506496,
        4172034488,
        1991878923,
        836252654,
        2503986788,
        892704164,
        1175044411,
        915558408,
        2355956005,
        1576386935,
        486274347,
        2320476144,
        290235230,
        2173958532,
        2054850355,
        829076693,
        1008783305,
        2799191123,
        974671884,
        2039399546,
        2544331560,
        1724186518,
        1366385731,
        231930939,
        3043585447,
        3152755397,
        1548997124,
        3542485198,
        1920580076,
        4095250127,
        4158100443,
        858571921,
        2876681749,
        2615928615,
        413143940,
        1542060199,
        1603315540,
        968254400,
        912735363,
        2090005780,
        2642253015,
        3806910890,
        1602133673,
        2059224401,
        1453196762,
        1084380722,
        1039509925,
        3132325248,
        1161987804,
        1063079544,
        64468829,
        2986232567,
        2779457187
      ];
      var BRANCH2_ORDERS = Crypto.unhex(
        "0f0704000908030a060b050d0e010c020f05080c0009020103070e060b0a0d04060500070c000a04080f010b0d09020e060b02050403080101070a000d0c090e0d070e0f0b0208030c0509010004060a0d0902060f0b0a040807000c0503010e0c090f07060f030e020d0405010b0a000c050a090e0802040407030f01060b000b0f0408020a0700090d06010e03050c0b060a0508020c03070f0e090d0001040906080f050800040a0b030d01020c0e090d0c0604070a03030f00080105020e01000d0f090a0b0e0402080703060c0501080a0c0f0905060b000304020e070d04080f000c0f0e0d0a01060207090503040205080d0b0a0606000e0f070c09030a08040f000b01060d0c0709030e05020a070b050f00020e0108030d0c0609040d070f08050f06040b0a0e0c090002030d0c020704010b0e0e08060f09050003"
      );
      function md5V3Step(kind, a, b, c, d, m, shift, constant) {
        let f;
        if (kind === 0) f = b & c | ~b & d;
        else if (kind === 1) f = b & d | c & ~d;
        else if (kind === 2) f = b ^ c ^ d;
        else f = c ^ (b | ~d);
        return b + rotl(a + f + m + constant | 0, shift) | 0;
      }
      function md5SumV3(message, countV2, orders, countV1) {
        const sv = new Array(BRANCH2_SV.length);
        for (let i = 0; i < sv.length; i++) sv[i] = ror(BRANCH2_SV[i], countV1);
        const start = [
          ror(2044785403, countV2),
          ror(3367314800, countV2),
          ror(3955423437, countV2),
          ror(2081443219, countV2)
        ];
        const endCount = countV2 + 6 & 255;
        const end = [
          ror(431900774, endCount),
          ror(3898181300, endCount),
          ror(3785044590, endCount),
          ror(1909577684, endCount)
        ];
        const m = new Array(16);
        for (let i = 0; i < 16; i++) m[i] = readLe32(message, i * 4);
        let a = start[0];
        let b = start[1];
        let c = start[2];
        let d = start[3];
        const shifts0 = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22];
        const shifts1 = [5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20];
        const shifts2 = [4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23];
        const shifts3 = [6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21];
        for (let kind = 0; kind < 4; kind++) {
          const shifts = kind === 0 ? shifts0 : kind === 1 ? shifts1 : kind === 2 ? shifts2 : shifts3;
          const offset = kind * 16;
          for (let i = 0; i < 16; i++) {
            const phase = i & 3;
            const mm = m[orders[offset + i] & 255];
            const cc = sv[offset + i];
            let next;
            if (phase === 0) next = md5V3Step(kind, a, b, c, d, mm, shifts[i], cc);
            else if (phase === 1) next = md5V3Step(kind, d, a, b, c, mm, shifts[i], cc);
            else if (phase === 2) next = md5V3Step(kind, c, d, a, b, mm, shifts[i], cc);
            else next = md5V3Step(kind, b, c, d, a, mm, shifts[i], cc);
            if (phase === 0) a = next;
            else if (phase === 1) d = next;
            else if (phase === 2) c = next;
            else b = next;
          }
        }
        const ret = Buffer.alloc(16);
        putLe32(ret, 0, start[0] + a ^ end[0]);
        putLe32(ret, 4, start[1] + b ^ end[1]);
        putLe32(ret, 8, start[2] + c ^ end[2]);
        putLe32(ret, 12, start[3] + d ^ end[3]);
        return Buffer.concat([ret, le32(sumMd5(ret))]);
      }
      function branch2F13(iv, querySm3, bodyMd5, tsBytes, khronos) {
        const v = (iv & 13) * 86;
        const ivV0 = (v >>> 15 & 255) + (v >>> 8 & 255);
        const n1 = [2306929307, 3948190847, 2961647323, 3557602790, 3908393444][ivV0];
        const countV1 = n1 + khronos + 1 & 255;
        const countV2 = n1 + khronos | 0;
        const shift = countV2 + 5 & 7;
        const seed = [132, 150, 119, 157, 212, 21, 11, 248];
        const pad = Buffer.alloc(8);
        for (let i = 0; i < 8; i++) pad[i] = (seed[i] | seed[i] << 8) >> shift & 255;
        const input = Buffer.concat([
          querySm3,
          bodyMd5,
          tsBytes,
          pad,
          Crypto.unhex("a0010000")
        ]);
        const from = ivV0 << 6;
        const to = ivV0 + 1 << 6;
        const orders = BRANCH2_ORDERS.subarray(from, to);
        return md5SumV3(input, countV2, orders, countV1);
      }
      var HASH_TABLE = [
        3954593711,
        128638146,
        3476129727,
        3759225087,
        1829502207,
        1513137086,
        3021657656,
        873991864,
        4063488879,
        2980414668,
        3435335111,
        1204935505,
        3579204574,
        1890078625,
        1464286226,
        4151247496,
        738688778,
        3658336976,
        4223168364,
        4257533696,
        1753874957,
        3866543782,
        2362848139,
        440175886,
        3437801579,
        1792077067,
        2689738519,
        3698437251,
        579197809,
        3585400230,
        1936688720,
        1700802668,
        1635574438,
        3827515774,
        172024131,
        1414414386,
        2296380202,
        1902910176,
        1279687304,
        95566771,
        3788552294,
        3131301048,
        2922607827,
        3275233872,
        386070363,
        4268598120,
        4038381384,
        1309670328,
        1923797261,
        650459709,
        4072464630,
        3025499521,
        1243971549,
        2352054946,
        2869640070,
        1029569300,
        1326462516,
        3548074711,
        1146027798,
        3943314385,
        1822977902,
        2640807,
        137919738,
        1605596550
      ];
      function hashF13(querySm3, bodyMd5, tsBytes, khronos) {
        const iv = getIv(getIv(getIv(539167016, querySm3), bodyMd5), tsBytes);
        const low = iv & 15;
        const ivV0 = low * 171 >> 9;
        const branch = low - ivV0 * 3;
        if (branch === 2) return branch2F13(iv, querySm3, bodyMd5, tsBytes, khronos);
        if (branch !== 0) {
          return Buffer.concat([
            querySm3.subarray(0, 16),
            bodyMd5,
            le32(sumMd5(Buffer.concat([querySm3, bodyMd5])))
          ]);
        }
        const ivV1List = [3299313024, 3015769401, 3314308742, 3383376807, 4121406962, 2520526545];
        const ivV1 = ivV1List[ivV0] | 0;
        const countV1 = ivV1 + khronos + 1 & 255;
        const countV2 = ivV1 + khronos | 0;
        const tt = new Array(HASH_TABLE.length);
        for (let i = 0; i < tt.length; i++) tt[i] = ror(HASH_TABLE[i], countV1);
        const n0 = countV2 + 2 & 7;
        const seed = [250, 69, 97, 215];
        const pad = Buffer.alloc(seed.length);
        for (let i = 0; i < seed.length; i++) pad[i] = (seed[i] | seed[i] << 8) >> n0 & 255;
        const data = Buffer.concat([
          querySm3,
          bodyMd5,
          tsBytes,
          pad,
          Crypto.unhex("00000000000001a0")
        ]);
        const di = new Array(data.length / 4 + 112 + 16).fill(0);
        let diLen = 0;
        for (let i = 0; i + 3 < data.length; i += 4) di[diLen++] = readBe32(data, i);
        let di0 = di[0];
        for (let i = 0; i < 112; i++) {
          const di1 = di[i + 1];
          const di14 = di[i + 14];
          const r1 = rotl(di1, 14) ^ rotl(di1, 25) ^ di1 >>> 3;
          const r2 = rotl(di14, 13) ^ rotl(di14, 15) ^ di14 >>> 10;
          di[diLen++] = di0 + di[i + 9] + r1 + r2 | 0;
          di0 = di1;
        }
        const initRaw = [
          2059030472,
          1729520903,
          1677982208,
          873419055,
          984304912,
          3005047866,
          2874125293,
          2152413264
        ];
        const init = new Array(8);
        for (let i = 0; i < 8; i++) init[i] = ror(initRaw[i], countV2 & 31);
        const chosenTable = [
          [101, 5, 7, 6, 3, 2, 1, 0, 5, 4, 3],
          [96, 0, 6, 7, 5, 3, 2, 1, 5, 4, 4],
          [96, 7, 6, 2, 1, 4, 0, 5, 4, 3, 5],
          [99, 3, 6, 2, 4, 5, 1, 0, 0, 7, 6],
          [96, 0, 5, 6, 7, 3, 1, 2, 5, 4, 4],
          [100, 2, 0, 3, 5, 4, 6, 7, 2, 1, 5]
        ];
        const chosen = chosenTable[ivV0];
        const d = init.slice();
        for (let i = 0; i < chosen[0]; i++) {
          const base = ivV1 + i | 0;
          const n0v = di[base & 127];
          const n1 = (d[chosen[3]] ^ d[chosen[4]]) & d[chosen[1]] ^ d[chosen[3]];
          const n2 = rotl(d[chosen[1]], 26) ^ rotl(d[chosen[1]], 21) ^ rotl(d[chosen[1]], 7);
          const n4 = n0v + n1 + n2 + tt[base & 63] + d[chosen[5]] | 0;
          const n5 = rotl(d[chosen[2]], 30) ^ rotl(d[chosen[2]], 19) ^ rotl(d[chosen[2]], 10);
          const n6 = d[chosen[2]] & d[chosen[6]] | (d[chosen[2]] | d[chosen[6]]) & d[chosen[7]];
          const n7 = n5 + n6 | 0;
          const old = d[chosen[9]];
          const last = d[d.length - 1];
          for (let k = d.length - 1; k >= 1; k--) d[k] = d[k - 1];
          d[0] = last;
          d[chosen[10]] = n7 + n4 | 0;
          d[chosen[8]] = old + n4 | 0;
        }
        const ret = Buffer.alloc(32);
        for (let i = 0; i < 8; i++) putBe32(ret, i * 4, d[i] + init[i] | 0);
        for (let i = 0; i < 16; i++) ret[i] = ret[i] ^ ret[i + 16];
        return Buffer.concat([ret.subarray(0, 16), le32(sumMd5(ret.subarray(0, 16)))]);
      }
      function rc4Gorgon(data, key) {
        const s = new Array(256);
        for (let i2 = 0; i2 < 256; i2++) s[i2] = i2;
        let j = 0;
        for (let i2 = 0; i2 < 256; i2++) {
          j = j + s[i2] + key[i2 % key.length] & 255;
          s[i2] = s[j];
        }
        const out = Buffer.alloc(data.length);
        let i = 0;
        j = 0;
        for (let k = 0; k < data.length; k++) {
          i += 1;
          const x = s[i];
          j += x;
          const y = s[j & 255];
          s[i] = y;
          out[k] = data[k] ^ s[y + y & 255];
        }
        return out;
      }
      function xGorgon(query, body, timestamp, random) {
        const q4 = md5(Buffer.from(query)).subarray(0, 4);
        const b4 = body != null && body.length > 0 ? md5(body).subarray(0, 4) : Buffer.alloc(4);
        const sdk = le32(67503104);
        const input = Buffer.concat([q4, b4, Buffer.alloc(4), sdk, be32(timestamp | 0)]);
        const key = [74, 64, 22, random >> 8 & 255, 71, 108, 1, random & 255];
        const out = rc4Gorgon(input, key);
        for (let i = 0; i < out.length; i++) {
          const value = rotl8(out[i] & 255);
          const next = i + 1 < out.length ? out[i + 1] & 255 : out[0] & 255;
          out[i] = ~(reverseBits((next ^ value) & 255) ^ 20) & 255;
        }
        return Crypto.hex(Buffer.concat([
          Crypto.unhex("8404"),
          Buffer.from([random & 255, random >> 8 & 255, 64, 1]),
          out
        ]));
      }
      var SBOX_V3 = Buffer.from(
        "+n0Ia5xZs0sEXznQOEqRmQBnpiCf9U2Ccybu3xhmgzOAAxn72f6uqqmwUsYL83klTni0NqxdGieeiNu9PGPsSRXBMB/cuFbUbM3KCUPINaPvHvSW0vwOcnuUhNHqRVpiAj/TEoE0K91+5ijypUYTATsh9mE3KSoN7Yyvv51cuyR2D3XkU4nhmI2xmmVwT1RMWKtub4sjxAcRDLrPoKSO2AU9FLLadMPX577Wf95IFj6FkKFVt3dCIsmGUC4X+WQxLJvxbRxEaOPpqJOXyzJX6+Vxaq3AzMfF/WAdoi1Hp+JRaV56zgpBtpWP97mH4DoGEIq1+FvV8LyS/3wvwugbQOwb2r26mJEMsiuDQTRn+wrYdrVGBVlhI3WQhyrjUBVMrLF5667llUcEaPCGPVGLD8qO5LlO8hKCvA7V9+8oJc9bXelqVQLhM76T5/WtnT45JKji+hdX0HoNCDDWuKON/QeaxB5uImSX0h2wv0VmP2zd2yeApxHcpsVS+MC2yFwAc2B7oBkTqsk1SEvTpM2fmfMQREBUfin0Bh+iq6EvPPavhWI2IX9e3yAas7Tm/3KEj2UmlFp36kN4x0rMLBRrxuh0U/zUHM4xcAMYjJY4MonxOl/X+alpt2M3WMI7w3HLnpIBigtNiJu7T21v4P6lSd5WFgntnMEt7oF92XzRLkJbTcGmXepE/UVOG6E/0YnhfS+q26utWcuxzpooyeD2cDlK1/8w9d28VzsRjbLuALbmGlp8+d7EzS6Au7lMpZ+ECMZvQmzwJ+eLOpxR+2chdUExp8ogQyq3v9l68rX4jCwjg0+PYKAEEzcU4wHFY2ZcdIHfWL1okD3SszT0GZMyKdZJrg1L2AeerB4tC0C4crp2EHGo5FYdSP7lwkeR2ocmnR+Ia8CYviUJlzOjhRZef9xuVOn3qcjow3fQgivsAmKKkg4+sA8F8/GWeDiGNhg8JM8KtFPMYWWkx5TVFX5t73kiNRJqjlIGVXtGZFCV4gzt0xcDopuZ6xz8r9Rzafpf9ywev8jh8592gHFIqpStZPuJxmDDMrNN0uBE3V+oscdoIzTJbRJ/t+sVvqnReJOgDJKk10fjisJwqyZBmnmn2BSFj8BvVtCMEbkuPOKdzw7eA11GPs04Qw8zWtkaZWwiO/wwpojqN6K0jY5RnNZA7vn4hPSul+nKCkVnVwQvg1zVxcSCtqORmB9KrJaBbssbCQivGJVJfVTt+hYxOtq4ZvWl8f4QAQZ0zGPffCgl9s6yT4vlvIdpu4YhBwA25wtQWZsc6GJYGWHyvSdeuh3mmUI9DSq13Fsp8C1MU3tqc04/df9LoTUXVXI5INOw/e8C7Hd+5CvbkMEFnnrUUmskEw==",
        "base64"
      );
      function aesSrc(data, idx) {
        return idx < data.length ? data[idx] & 255 : 0;
      }
      function aesPut(out, idx, value) {
        if (idx >= 0 && idx < out.length) out[idx] = value & 255;
      }
      function aesMatrix(bytes) {
        const rows = new Array(4);
        for (let i = 0; i < 4; i++) {
          rows[i] = new Array(4);
          for (let j = 0; j < 4; j++) rows[i][j] = bytes[i * 4 + j] & 255;
        }
        return rows;
      }
      function aesFlat(rows) {
        const b = Buffer.alloc(16);
        for (let i = 0; i < 4; i++) {
          for (let j = 0; j < 4; j++) b[i * 4 + j] = rows[i][j] & 255;
        }
        return b;
      }
      function aesXt(x) {
        return (x << 1 ^ ((x & 128) !== 0 ? 27 : 0)) & 255;
      }
      function aesMix(rows) {
        for (let i = 0; i < 4; i++) {
          const t = rows[0][i] ^ rows[1][i] ^ rows[2][i] ^ rows[3][i];
          const u = rows[0][i];
          rows[0][i] ^= t ^ aesXt(rows[0][i] ^ rows[1][i]);
          rows[1][i] ^= t ^ aesXt(rows[1][i] ^ rows[2][i]);
          rows[2][i] ^= t ^ aesXt(rows[2][i] ^ rows[3][i]);
          rows[3][i] ^= t ^ aesXt(rows[3][i] ^ u);
        }
      }
      var AesV3 = class {
        constructor(key, khronos) {
          this.wordSize = khronos & 3;
          this.box = SBOX_V3.subarray(this.wordSize * 256, (this.wordSize + 1) * 256);
          const con2Table = [[1, 0, 2, 3], [2, 0, 3, 1], [0, 1, 3, 2], [1, 0, 2, 3]];
          const orderTable = [
            [0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3],
            [0, 9, 14, 15, 4, 13, 2, 7, 8, 1, 6, 3, 12, 5, 10, 11],
            [0, 9, 14, 7, 4, 13, 2, 11, 8, 1, 6, 3, 12, 5, 10, 15],
            [0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3]
          ];
          this.con2 = con2Table[this.wordSize];
          this.order = orderTable[this.wordSize];
          this.wire = [5, 6, 2, 4, 3, 1, 0, 7];
          this.compact = [1, 6, 0, 7, 2, 4, 5, 3];
          const init = [3389152732, 2185086278, 3376547203, 3264750175][this.wordSize];
          const initial = Buffer.alloc(16);
          for (let i = 0; i < 4; i++) putLe32(initial, i * 4, init);
          const mk = xorBytes(initial, key);
          const expanded = Buffer.concat([mk, Buffer.alloc(32)]);
          let rounds = 8;
          for (let i = 4; i < 12; i++) {
            const at = 4 * (i - 1);
            let a = expanded[at] & 255;
            let b = expanded[at + 1] & 255;
            let c = expanded[at + 2] & 255;
            let d = expanded[at + 3] & 255;
            if ((i & 3) === 0) {
              const t = (init >>> (rounds & 24) ^ this.box[b] & 255) & 255;
              b = this.box[c] & 255;
              c = this.box[d] & 255;
              d = this.box[a] & 255;
              a = t;
            }
            rounds += 2;
            expanded[at + 4] = (a ^ expanded[at - 12] & 255) & 255;
            expanded[at + 5] = (b ^ expanded[at - 11] & 255) & 255;
            expanded[at + 6] = (c ^ expanded[at - 10] & 255) & 255;
            expanded[at + 7] = (d ^ expanded[at - 9] & 255) & 255;
          }
          this.keys = new Array(12);
          for (let i = 0; i < 12; i++) {
            this.keys[i] = new Array(4);
            for (let j = 0; j < 4; j++) this.keys[i][j] = expanded[i * 4 + j] & 255;
          }
        }
        add(rows, key) {
          for (let i = 0; i < 4; i++) {
            for (let j = 0; j < 4; j++) rows[i][j] ^= key[i][j];
          }
        }
        addCon(rows, ks) {
          for (let i = 0; i < 4; i++) {
            for (let j = 0; j < 4; j++) rows[i][j] ^= ks[i][this.con2[j]];
          }
        }
        sub(rows) {
          for (let i = 0; i < 4; i++) {
            for (let j = 0; j < 4; j++) rows[i][j] = this.box[rows[i][j]] & 255;
          }
          const old = new Array(4);
          for (let i = 0; i < 4; i++) old[i] = rows[i].slice();
          for (let i = 0; i < 4; i++) rows[i] = old[this.con2[i]];
        }
        shift(rows) {
          const b = aesFlat(rows);
          for (let i = 0; i < 16; i++) rows[i / 4 | 0][i % 4] = b[this.order[i]] & 255;
        }
        shiftCon(rows) {
          const old = new Array(4);
          for (let i = 0; i < 4; i++) old[i] = rows[i].slice();
          for (let i = 0; i < 4; i++) {
            for (let j = 0; j < 4; j++) rows[i][j] = old[i][this.con2[j]];
          }
        }
        block(value) {
          const rows = aesMatrix(value);
          const k0 = this.subKeys(0);
          this.addCon(rows, k0);
          for (let i = 1; i < 3; i++) {
            this.sub(rows);
            this.shift(rows);
            if (i === 1) {
              this.shiftCon(rows);
              aesMix(rows);
            }
            this.addCon(rows, this.subKeys(i * 4));
          }
          this.add(rows, this.subKeys(4));
          return aesFlat(rows);
        }
        subKeys(from) {
          const out = new Array(4);
          for (let i = 0; i < 4; i++) out[i] = this.keys[from + i].slice(0, 4);
          return out;
        }
        /** 加密：明文具化到 32 字节 -> CBC 两轮 -> 按 key 逐位回填源数据，末尾缀 key 末字节。 */
        encrypt(data, iv) {
          const wire = this.wire;
          const compact = this.compact;
          const plaintext = Buffer.alloc(32);
          for (let i = 0; i < 31; i++) {
            const at = i * 8;
            let acc = 0;
            for (let j = 0; j < 8; j++) {
              acc |= (aesSrc(data, at + j) >>> wire[j] & 1) << compact[j];
            }
            plaintext[i] = acc & 255;
          }
          plaintext[31] = 1;
          const blocks = [];
          let previous = Buffer.from(iv);
          for (let i = 0; i < plaintext.length; i += 16) {
            const value = this.block(xorBytes(plaintext.subarray(i, i + 16), previous));
            blocks.push(value);
            previous = value;
          }
          const key = Buffer.concat(blocks);
          const out = Buffer.from(data);
          for (let i = 0; i < 31; i++) {
            const at = i * 8;
            const k = key[i] & 255;
            for (let j = 0; j < 8; j++) {
              const bit = wire[j];
              const mask = 1 << bit & 255;
              aesPut(
                out,
                at + j,
                aesSrc(out, at + j) & (~mask & 255) | (k >>> compact[j] & 1) << bit
              );
            }
          }
          return Buffer.concat([key.subarray(key.length - 1, key.length), out]);
        }
      };
      function xmxor(data, key) {
        const encoded = Buffer.alloc(data.length);
        for (let i = 0; i < data.length; i++) {
          const at = i * 4 & 28;
          const d0 = key[at] & 255;
          const d1 = key[at + 1] & 255;
          let d2 = rotl8(data[i] & 255) + d0;
          d2 = ~d2 ^ d1;
          d2 = rotl8_3(d2 & 255);
          d2 = d2 + d1 & 255;
          d2 = (d2 ^ d0) & 255;
          encoded[data.length - i - 1] = ~d2 & 255;
        }
        const last = (encoded[encoded.length - 1] ^ encoded[encoded.length - 2]) & 255;
        const first = encoded[0] & 255;
        encoded[0] = ~last + first & 255;
        encoded[1] = (encoded[0] ^ encoded[encoded.length - 1] ^ 254) + encoded[1] & 255;
        encoded[2] = encoded[2] + (last - first ^ rotl8_3(encoded[1] & 255) ^ 2) & 255;
        for (let i = 0; i < encoded.length - 4; i++) {
          const temp = rotl8_3(encoded[i + 2] & 255) ^ encoded[i + 1] ^ i + 3;
          encoded[i + 3] = ~temp + encoded[i + 3] & 255;
        }
        encoded[encoded.length - 1] = (encoded[encoded.length - 1] ^ encoded[encoded.length - 2]) & 255;
        let sum = 0;
        for (let i = 0; i < encoded.length - 1; i++) sum += encoded[i + 1] & 255;
        encoded[0] = (encoded[0] ^ encoded[1]) + sum & 255;
        return encoded;
      }
      function keyHash(signKey, random) {
        const hash = sm3(Buffer.concat([signKey, le32(random), signKey]));
        const d1 = random >> 16 & 255;
        let d2 = (d1 << 11 | random >>> 24) ^ d1 >> 5 ^ d1;
        d2 = ~d2;
        return [hash, le32(d2)];
      }
      var MEDUSA_SIGN_KEY = Crypto.unhex(
        "8ebdfa3806ecc5cee79423e6029ed82540bc2218bb7eaef71cb691f7aa8aa2f5"
      );
      var MEDUSA_AES_KEY = Crypto.unhex("f1593376766ea98d34f31b057a9d5be4");
      var MEDUSA_AES_IV = Crypto.unhex("1fe109a4125283f418de9e051a969e12");
      var MEDUSA_MAGIC16 = Crypto.unhex("f7e85ffad7d7dc3bd62ac87057cf6118");
      var MEDUSA_MAGIC8 = Crypto.unhex("4001000000000000");
      var PROCESS_NONCE = crypto.randomBytes(18).toString("base64url");
      var PROCESS_STARTED = Date.now();
      function randomBytes(n) {
        return crypto.randomBytes(n);
      }
      function rndInt(n) {
        return crypto.randomInt(n);
      }
      function rndInt32() {
        return crypto.randomBytes(4).readUInt32BE(0);
      }
      function deviceProto(deviceId, version) {
        return proto([
          [1, 1, "sint"],
          [2, 2, "sint"],
          [3, "8662"],
          [4, deviceId],
          [5, PROCESS_NONCE],
          [6, "!noperm!"],
          [7, -888888, "sint"],
          [8, -888888, "sint"],
          [9, 3, "sint"],
          [10, -888888, "sint"],
          [11, "!notset!"],
          [12, "Asia/Shanghai,8"],
          [13, "zh_CN"],
          [14, 4, "sint"],
          [16, 0, "float"],
          [17, 0, "float"],
          [18, 0, "float"],
          [19, 0, "float"],
          [20, 0, "float"],
          [21, 0, "float"],
          [22, "16"],
          [23, 41, "sint"],
          [24, 36, "sint"],
          [25, PROCESS_STARTED, "sint"],
          [26, PROCESS_STARTED, "sint"],
          [27, PROCESS_STARTED, "sint"],
          [28, PROCESS_STARTED, "sint"],
          [29, -1, "sint"],
          [30, "25053RT47C"],
          [31, "Redmi"],
          [32, "25053RT47C"],
          [33, "25053RT47C"],
          [34, "Xiaomi"],
          [35, "Redmi"],
          [36, "Redmi"],
          [38, 31, "sint"]
        ]);
      }
      function buildMedusa(url, body, khronos, deviceId, version) {
        const bodyMd5 = body != null && body.length > 0 ? md5(body) : Buffer.alloc(16);
        const query = queryOf(url);
        const querySm3 = sm3(Buffer.from(query));
        const ts = le32(khronos | 0);
        const queryBodyTs = hashF13(querySm3, bodyMd5, ts, khronos);
        const messageRand = randomBytes(4);
        const messageRandU = readLe32(messageRand, 0) >>> 0;
        const envLaunch = 100 + rndInt(21);
        const envPid = 10001 + rndInt(2e3);
        const env = proto([
          [1, envLaunch, "sint"],
          [2, 146331399, "sint"],
          [3, 146331396, "sint"],
          [5, 7, "sint"],
          [6, "v04.06.04.03-bugfix"],
          [7, envPid, "sint"],
          [12, deviceProto(deviceId, version), "message"],
          [13, proto([
            [1, Math.floor(Date.now() / 1e3), "sint"],
            [2, -2, "sint"],
            [4, 200, "sint"]
          ]), "message"],
          [14, version]
        ]);
        const queryHash = sm3(Buffer.concat([
          Buffer.from(query),
          bodyMd5,
          Buffer.from("none")
        ]));
        const nested = proto([
          [1, 111, "sint"],
          [2, 10, "sint"],
          [3, 694367, "sint"],
          [5, 586952199, "sint"]
        ]);
        const message = proto([
          [1, MEDUSA_MAGIC16, "bytes"],
          [2, 3, "sint"],
          [3, messageRandU, "sint"],
          [4, "8662"],
          [5, deviceId],
          [6, "1588093228"],
          [7, version],
          [8, "v04.06.04-ml-android"],
          [9, 67503104, "sint"],
          [10, MEDUSA_MAGIC8, "bytes"],
          [12, khronos, "sint"],
          [13, queryBodyTs, "bytes"],
          [14, querySm3.subarray(0, 6), "bytes"],
          [15, nested, "message"],
          [16, PROCESS_NONCE],
          [17, khronos, "sint"],
          [19, queryHash, "bytes"],
          [20, "none"],
          [21, 312, "sint"],
          [23, env, "message"],
          [24, '{"cmr":16777216,"cmr2":16777216,"un_h":1879194040,"vpn":0,"kd":0,"fkd":3672518972,"pd":-1872573247,"dyn":"","do":0,"tk":true}']
        ]);
        const random = rndInt32();
        const hs = keyHash(MEDUSA_SIGN_KEY, random);
        const hash = hs[0];
        const seed = hs[1];
        let transformed = xmxor(message, hash);
        transformed = Buffer.concat([MEDUSA_MAGIC8, transformed]);
        for (let i = 0, j = transformed.length - 1; i < j; i++, j--) {
          const t = transformed[i];
          transformed[i] = transformed[j];
          transformed[j] = t;
        }
        for (let i = 0; i < transformed.length; i++) {
          transformed[i] = (transformed[i] ^ seed[~i & 3]) & 255;
        }
        const check = (querySm3[0] & 63) << 14 | 402653185 | (queryBodyTs[0] & 63) << 8 | 0;
        const xmRand = rndInt32();
        const packed = Buffer.concat([
          Buffer.from([53]),
          le32(xmRand),
          le32(check),
          transformed,
          Buffer.from([random >> 16 & 255, random >> 24 & 255])
        ]);
        const encrypted = new AesV3(MEDUSA_AES_KEY, khronos).encrypt(packed, MEDUSA_AES_IV);
        const versionBytes = Crypto.unhex("03000000f7e85ffad7d7dc3bd62ac87057cf6118");
        const prefix = Buffer.alloc(20);
        for (let i = 0; i < 20; i += 4) {
          putLe32(prefix, i, readLe32(versionBytes, i) ^ (khronos | 0));
        }
        return Buffer.concat([
          prefix,
          Buffer.from([random & 255, random >> 8 & 255, 0, 1]),
          encrypted
        ]).toString("base64");
      }
      function helios(khronos) {
        return heliosWith(khronos, rndInt32());
      }
      function heliosWith(khronos, random, license) {
        const digest = md5(Buffer.concat([le32(random), Buffer.from("8662")]));
        const hex = digest.toString("hex");
        const ascii = Buffer.from(hex, "ascii");
        const words = new Array(4);
        for (let i = 0; i < 4; i++) words[i] = readU64Le(ascii, i * 8);
        const queue = [words[2], words[3]];
        let b0 = words[0];
        let b8 = words[1];
        const table = new Array(35);
        table[0] = words[0];
        for (let i = 0; i < 34; i++) {
          let x8 = BigInt.asUintN(64, rotr64(b8, 8) + b0);
          x8 = BigInt.asUintN(64, x8 ^ BigInt(i));
          queue.push(x8);
          x8 = BigInt.asUintN(64, x8 ^ rotr64(b0, 61));
          table[i + 1] = x8;
          b0 = x8;
          b8 = queue.shift();
        }
        const text = String(khronos) + "-" + (license || "1588093228") + "-8662";
        const tb = Buffer.from(text);
        const padLen = Math.floor((tb.length + 1 + 15) / 16) * 16;
        const pad = Buffer.alloc(padLen);
        pad.fill(16 - tb.length % 16 & 255);
        tb.copy(pad, 0);
        const output = [];
        for (let at = 0; at < pad.length; at += 16) {
          let a = readU64Le(pad, at);
          let b = readU64Le(pad, at + 8);
          for (let i = 0; i < 34; i++) {
            b = BigInt.asUintN(64, table[i] ^ BigInt.asUintN(64, a + rotr64(b, 8)));
            a = BigInt.asUintN(64, b ^ rotr64(a, 61));
          }
          const block = Buffer.alloc(16);
          putU64Le(block, 0, a);
          putU64Le(block, 8, b);
          output.push(block);
        }
        const all = [le32(random), ...output];
        return Buffer.concat(all).toString("base64");
      }
      function branchV5(queryStr, body, khronos) {
        const bodyMd5 = body != null && body.length > 0 ? md5(body) : Buffer.alloc(16);
        const q = sm3(Buffer.from(queryStr));
        const iv = getIv(getIv(getIv(539167016, q), bodyMd5), le32(khronos | 0));
        return (iv & 15) === 12 ? 0 : 1;
      }
      function signV5Encode(value) {
        return encodeURIComponent(String(value)).replace(/[!'()]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());
      }
      function encodeV5Query(values) {
        const parts = [];
        for (const k of Object.keys(values)) {
          parts.push(signV5Encode(k) + "=" + signV5Encode(String(values[k])));
        }
        return parts.join("&");
      }
      function signPlaybackV5(base, values, body, now) {
        const ts = Math.floor(now / 1e3);
        for (let offset = 0; offset <= 1023; offset++) {
          const ticket = now + offset;
          const query = encodeV5Query(Object.assign({}, values, { _rticket: String(ticket) }));
          if (branchV5(query, body, ts) !== 0) continue;
          const url = base + "?" + query;
          const all = ThlSign.sign(url, body, ts, values);
          const headers = {
            "x-khronos": all["x-khronos"],
            "x-helios": all["x-helios"],
            "x-medusa": all["x-medusa"]
          };
          if (body != null && body.length > 0) {
            headers["Content-Type"] = "application/json; charset=utf-8";
            headers["x-ss-stub"] = md5(body).toString("hex").toUpperCase();
          }
          return { url, headers };
        }
        throw new Error("\u65E0\u6CD5\u751F\u6210\u64AD\u653E\u7B7E\u540D");
      }
      function branchOf(url, body, khronos) {
        const bodyMd5 = body != null && body.length > 0 ? md5(body) : Buffer.alloc(16);
        const q = sm3(Buffer.from(queryOf(url)));
        const iv = getIv(getIv(getIv(539167016, q), bodyMd5), le32(khronos | 0));
        const low = iv & 15;
        return low - (low * 171 >> 9) * 3;
      }
      function queryOf(url) {
        const i = url.indexOf("?");
        return i < 0 ? "" : url.substring(i + 1);
      }
      function sign(url, body, khronos) {
        const ts = khronos === void 0 || khronos === null ? Math.floor(Date.now() / 1e3) : khronos;
        const gorgonRandom = rndInt(65536);
        const query = queryOf(url);
        const out = {};
        out["x-gorgon"] = xGorgon(query, body, ts, gorgonRandom);
        out["x-khronos"] = String(ts);
        out["x-ladon"] = be32(ts | 0).toString("base64");
        out["x-argus"] = le32(ts | 0).toString("base64");
        out["x-helios"] = helios(ts);
        out["x-medusa"] = buildMedusa(
          url,
          body,
          ts,
          paramOf(query, "device_id", "0"),
          paramOf(query, "version_name", "7.1.3.32")
        );
        return out;
      }
      function paramOf(query, key, fallback) {
        for (const kv of query.split("&")) {
          const eq = kv.indexOf("=");
          if (eq <= 0) continue;
          if (kv.substring(0, eq) === key) {
            const v = kv.substring(eq + 1);
            if (v.length > 0) return v;
          }
        }
        return fallback;
      }
      function hashF13Hex(queryText, bodyText, khronos) {
        return hashF13(
          sm3(Buffer.from(queryText)),
          md5(Buffer.from(bodyText)),
          le32(khronos),
          khronos
        ).toString("hex");
      }
      module.exports = {
        sign,
        branchOf,
        hashF13Hex,
        // v5 播放签名（供 app-source.js 取直链使用）
        signPlaybackV5,
        branchV5,
        AesV3
      };
    }
  });

  // entry.js
  var { Buffer: BufferImpl } = require_buffer();
  if (typeof globalThis.Buffer === "undefined") globalThis.Buffer = BufferImpl;
  {
    const origToString = BufferImpl.prototype.toString;
    BufferImpl.prototype.toString = function(enc, start, end) {
      if (enc === "base64url") {
        return origToString.call(this, "base64", start, end).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
      }
      return origToString.call(this, enc, start, end);
    };
    const origFrom = BufferImpl.from;
    BufferImpl.from = function(value, enc, ...rest) {
      if (enc === "base64url") {
        const s = String(value).replace(/-/g, "+").replace(/_/g, "/");
        return origFrom.call(this, s, "base64", ...rest);
      }
      return origFrom.call(this, value, enc, ...rest);
    };
  }
  var PureSign = require_pure_sign();
  globalThis.FalconSign = {
    /**
     * @param {string} base 接口 URL（不含 query）
     * @param {string} valuesJson 有序 query 参数（JSON 对象字符串）
     * @param {string} bodyHex 请求体 hex（空串表示无 body）
     * @param {number} now 毫秒时间戳
     * @returns {string} JSON: {ok, url, headers} | {ok:false, error}
     */
    signPlaybackV5(base, valuesJson, bodyHex, now) {
      try {
        const values = JSON.parse(valuesJson);
        const body = bodyHex ? Buffer.from(bodyHex, "hex") : null;
        const r = PureSign.signPlaybackV5(base, values, body, Number(now));
        return JSON.stringify({ ok: true, url: r.url, headers: r.headers });
      } catch (e) {
        return JSON.stringify({ ok: false, error: String(e && e.message || e) });
      }
    },
    /** 旧签名（六头全出），用于比对 thl-sign 是否正常加载。 */
    signAll(url, bodyHex, now, deviceJson) {
      try {
        const body = bodyHex ? Buffer.from(bodyHex, "hex") : null;
        const h = require_thl_sign().sign(url, body, Number(now), JSON.parse(deviceJson));
        return JSON.stringify({ ok: true, headers: h });
      } catch (e) {
        return JSON.stringify({ ok: false, error: String(e && e.message || e) });
      }
    },
    /** 环境自检：确认 Buffer / md5 / sm3 / aes 都可用。 */
    selfTest() {
      const out = {};
      try {
        out.buffer = Buffer.from("61", "hex").toString("hex") === "61";
        const crypto = require_shim_crypto();
        out.md5 = crypto.createHash("md5").update("abc").digest("hex") === "900150983cd24fb0d6963f7d28e17f72";
        out.sm3 = crypto.createHash("sm3").update("abc").digest("hex") === "66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0";
        const c = crypto.createCipheriv(
          "aes-128-ctr",
          Buffer.alloc(16, 0),
          Buffer.alloc(16, 0)
        );
        out.aes = c.update(Buffer.from("00".repeat(16), "hex")).toString("hex") === "66e94bd4ef8a2c3b884cfa59ca342b2e";
      } catch (e) {
        out.error = String(e && e.message || e);
      }
      out.all = out.buffer && out.md5 && out.sm3 && out.aes;
      return JSON.stringify(out);
    }
  };
})();
