//! Type-safe wrapper for the browser Web Crypto API (`window.crypto`).
//! https://developer.mozilla.org/en-US/docs/Web/API/Crypto

const std = @import("std");
const webapi = @import("webapi.zig");
const zjb = webapi.zjb;

const Crypto = @This();

/// Maximum byte length allowed per `Crypto.getRandomValues` call by the Web Crypto spec.
pub const max_random_values_bytes: usize = 65536;

/// Underlying JavaScript `Crypto` handle.
handle: zjb.Handle = .null,

/// Null `Crypto` sentinel.
pub const @"null": Crypto = .{};

/// Supported cryptographic hash algorithms for `SubtleCrypto.digest` and key parameters.
pub const HashAlgorithm = enum {
    @"SHA-1",
    @"SHA-256",
    @"SHA-384",
    @"SHA-512",
};

/// Supported key serialization formats for `SubtleCrypto.importKey`, `exportKey`,
/// `wrapKey`, and `unwrapKey`.
pub const KeyFormat = enum {
    raw,
    pkcs8,
    spki,
    jwk,
};

/// Allowed operations for a `CryptoKey`.
pub const KeyUsage = enum {
    encrypt,
    decrypt,
    sign,
    verify,
    deriveKey,
    deriveBits,
    wrapKey,
    unwrapKey,
};

/// Classification of a `CryptoKey` (`CryptoKey.type`).
pub const KeyType = enum {
    public,
    private,
    secret,
};

/// Returns `true` if `window.crypto` is available in the current environment.
pub fn isSupported() bool {
    const window = zjb.global("window");
    const c = window.get("crypto", zjb.Handle);
    defer c.release();
    return !c.isNull();
}

/// Returns a non-owning `Crypto` handle referencing the global `crypto` object.
/// https://developer.mozilla.org/en-US/docs/Web/API/Window/crypto
pub fn global() Crypto {
    return .{ .handle = zjb.global("crypto").asHandle() };
}

/// Wraps an existing JavaScript `Crypto` handle.
pub fn fromHandle(handle: zjb.Handle) Crypto {
    std.debug.assert(!handle.isNull());
    std.debug.assert(@backingInt(handle) != 0);
    return .{ .handle = handle };
}

/// Returns `true` if the underlying JS handle is null or undefined.
pub fn isNull(self: Crypto) bool {
    return self.handle.isNull();
}

/// Releases the underlying JS handle.
pub fn release(self: Crypto) void {
    self.handle.release();
}

/// Returns the `SubtleCrypto` interface (`crypto.subtle`) for low-level
/// cryptographic operations. Note that `subtle` may be null in insecure contexts.
/// https://developer.mozilla.org/en-US/docs/Web/API/Crypto/subtle
pub fn subtle(self: Crypto) SubtleCrypto {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    return .{ .handle = self.handle.get("subtle", zjb.Handle) };
}

/// Fills `buf` with cryptographically strong random bytes using
/// `crypto.getRandomValues`. Slices larger than 65,536 bytes are automatically
/// filled in chunks to satisfy the Web Crypto quota limit.
/// https://developer.mozilla.org/en-US/docs/Web/API/Crypto/getRandomValues
pub fn getRandomValues(self: Crypto, buf: []u8) void {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    var offset: usize = 0;
    while (offset < buf.len) {
        const chunk_len = @min(buf.len - offset, max_random_values_bytes);
        const view = zjb.u8ArrayView(buf[offset .. offset + chunk_len]);
        defer view.release();
        self.handle.call("getRandomValues", .{view}, void);
        offset += chunk_len;
    }
}

/// Generates a cryptographically random value of type `T` (e.g. `u32`, `u64`, `[16]u8`).
pub fn random(self: Crypto, comptime T: type) T {
    var val: T = undefined;
    self.getRandomValues(std.mem.asBytes(&val));
    return val;
}

/// Returns a `std.Random` interface backed by `crypto.getRandomValues`.
pub fn stdRandom(self: *const Crypto) std.Random {
    return .{
        .ptr = @ptrCast(@constCast(self)),
        .fillFn = fillRandom,
    };
}

fn fillRandom(ptr: *anyopaque, buf: []u8) void {
    const self: *const Crypto = @ptrCast(@alignCast(ptr));
    self.getRandomValues(buf);
}

/// Generates a v4 UUID string using `crypto.randomUUID()` into `buf` (at least 36 bytes)
/// and returns the populated slice.
/// https://developer.mozilla.org/en-US/docs/Web/API/Crypto/randomUUID
pub fn randomUUID(self: Crypto, buf: []u8) []u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.call("randomUUID", .{}, zjb.Handle);
    defer h.release();
    return webapi.stringFromHandle(h, buf);
}

/// Generates a v4 UUID string using `crypto.randomUUID()` into a newly
/// allocated UTF-8 slice owned by the caller.
/// https://developer.mozilla.org/en-US/docs/Web/API/Crypto/randomUUID
pub fn randomUUIDAlloc(self: Crypto, allocator: std.mem.Allocator) ![]u8 {
    std.debug.assert(!self.handle.isNull());
    std.debug.assert(@backingInt(self.handle) != 0);
    const h = self.handle.call("randomUUID", .{}, zjb.Handle);
    defer h.release();
    return try webapi.stringFromHandleAlloc(allocator, h);
}

/// Type-safe wrapper for `CryptoKey`.
/// https://developer.mozilla.org/en-US/docs/Web/API/CryptoKey
pub const CryptoKey = struct {
    handle: zjb.Handle = .null,

    pub const @"null": CryptoKey = .{};

    /// Wraps an existing JavaScript `CryptoKey` handle.
    pub fn fromHandle(handle: zjb.Handle) CryptoKey {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns `true` if the underlying JS handle is null or undefined.
    pub fn isNull(self: CryptoKey) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JS handle.
    pub fn release(self: CryptoKey) void {
        self.handle.release();
    }

    /// Returns the `type` of the key (`public`, `private`, or `secret`), or `null` if unknown.
    /// https://developer.mozilla.org/en-US/docs/Web/API/CryptoKey/type
    pub fn keyType(self: CryptoKey) ?KeyType {
        std.debug.assert(!self.handle.isNull());
        const type_h = self.handle.get("type", zjb.Handle);
        defer type_h.release();
        if (type_h.isNull()) return null;
        var buf: [16]u8 = undefined;
        const s = webapi.stringFromHandle(type_h, &buf);
        return std.meta.stringToEnum(KeyType, s);
    }

    /// Returns whether the key may be extracted using `SubtleCrypto.exportKey` or `wrapKey`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/CryptoKey/extractable
    pub fn extractable(self: CryptoKey) bool {
        std.debug.assert(!self.handle.isNull());
        return self.handle.get("extractable", bool);
    }

    /// Returns the JS object describing the algorithm for which this key can be used.
    /// Caller owns the returned handle.
    /// https://developer.mozilla.org/en-US/docs/Web/API/CryptoKey/algorithm
    pub fn algorithm(self: CryptoKey) zjb.Handle {
        std.debug.assert(!self.handle.isNull());
        return self.handle.get("algorithm", zjb.Handle);
    }

    /// Returns the JS array of `KeyUsage` strings indicating what can be done with this key.
    /// Caller owns the returned handle.
    /// https://developer.mozilla.org/en-US/docs/Web/API/CryptoKey/usages
    pub fn usages(self: CryptoKey) zjb.Handle {
        std.debug.assert(!self.handle.isNull());
        return self.handle.get("usages", zjb.Handle);
    }
};

/// Type-safe wrapper for an asymmetric `CryptoKeyPair` (`{ publicKey, privateKey }`).
/// https://developer.mozilla.org/en-US/docs/Web/API/CryptoKeyPair
pub const CryptoKeyPair = struct {
    handle: zjb.Handle = .null,

    pub const @"null": CryptoKeyPair = .{};

    /// Wraps an existing JavaScript `CryptoKeyPair` handle.
    pub fn fromHandle(handle: zjb.Handle) CryptoKeyPair {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns `true` if the underlying JS handle is null or undefined.
    pub fn isNull(self: CryptoKeyPair) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JS handle.
    pub fn release(self: CryptoKeyPair) void {
        self.handle.release();
    }

    /// Returns the public key of the pair. Caller owns the returned `CryptoKey` handle.
    pub fn publicKey(self: CryptoKeyPair) CryptoKey {
        std.debug.assert(!self.handle.isNull());
        return .{ .handle = self.handle.get("publicKey", zjb.Handle) };
    }

    /// Returns the private key of the pair. Caller owns the returned `CryptoKey` handle.
    pub fn privateKey(self: CryptoKeyPair) CryptoKey {
        std.debug.assert(!self.handle.isNull());
        return .{ .handle = self.handle.get("privateKey", zjb.Handle) };
    }
};

/// Type-safe wrapper for `SubtleCrypto` (`window.crypto.subtle`).
/// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto
pub const SubtleCrypto = struct {
    handle: zjb.Handle = .null,

    pub const @"null": SubtleCrypto = .{};

    /// Wraps an existing JavaScript `SubtleCrypto` handle.
    pub fn fromHandle(handle: zjb.Handle) SubtleCrypto {
        std.debug.assert(!handle.isNull());
        std.debug.assert(@backingInt(handle) != 0);
        return .{ .handle = handle };
    }

    /// Returns `true` if the underlying JS handle is null or undefined.
    pub fn isNull(self: SubtleCrypto) bool {
        return self.handle.isNull();
    }

    /// Releases the underlying JS handle.
    pub fn release(self: SubtleCrypto) void {
        self.handle.release();
    }

    /// Computes a cryptographic digest of `data` using `algorithm`, returning a `Promise`
    /// that resolves to an `ArrayBuffer`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/digest
    pub fn digest(
        self: SubtleCrypto,
        algorithm: HashAlgorithm,
        data: []const u8,
    ) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        const view = zjb.u8ArrayView(data);
        defer view.release();
        const alg = webapi.constTagName(algorithm);
        return webapi.Promise.fromHandle(
            self.handle.call("digest", .{ alg, view }, zjb.Handle),
        );
    }

    /// Encrypts `data` with `key` and `algorithm`, returning a `Promise` that
    /// resolves to an `ArrayBuffer`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/encrypt
    pub fn encrypt(
        self: SubtleCrypto,
        algorithm: zjb.Handle,
        key: CryptoKey,
        data: []const u8,
    ) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!algorithm.isNull());
        std.debug.assert(!key.isNull());
        const view = zjb.u8ArrayView(data);
        defer view.release();
        return webapi.Promise.fromHandle(
            self.handle.call("encrypt", .{ algorithm, key.handle, view }, zjb.Handle),
        );
    }

    /// Decrypts `data` with `key` and `algorithm`, returning a `Promise` that
    /// resolves to an `ArrayBuffer`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/decrypt
    pub fn decrypt(
        self: SubtleCrypto,
        algorithm: zjb.Handle,
        key: CryptoKey,
        data: []const u8,
    ) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!algorithm.isNull());
        std.debug.assert(!key.isNull());
        const view = zjb.u8ArrayView(data);
        defer view.release();
        return webapi.Promise.fromHandle(
            self.handle.call("decrypt", .{ algorithm, key.handle, view }, zjb.Handle),
        );
    }

    /// Signs `data` with `key` and `algorithm`, returning a `Promise` that
    /// resolves to an `ArrayBuffer` containing the signature.
    /// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/sign
    pub fn sign(
        self: SubtleCrypto,
        algorithm: zjb.Handle,
        key: CryptoKey,
        data: []const u8,
    ) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!algorithm.isNull());
        std.debug.assert(!key.isNull());
        const view = zjb.u8ArrayView(data);
        defer view.release();
        return webapi.Promise.fromHandle(
            self.handle.call("sign", .{ algorithm, key.handle, view }, zjb.Handle),
        );
    }

    /// Verifies `signature` against `data` using `key` and `algorithm`, returning a
    /// `Promise` that resolves to a `boolean`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/verify
    pub fn verify(
        self: SubtleCrypto,
        algorithm: zjb.Handle,
        key: CryptoKey,
        signature: []const u8,
        data: []const u8,
    ) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!algorithm.isNull());
        std.debug.assert(!key.isNull());
        const sig_view = zjb.u8ArrayView(signature);
        defer sig_view.release();
        const data_view = zjb.u8ArrayView(data);
        defer data_view.release();
        return webapi.Promise.fromHandle(
            self.handle.call(
                "verify",
                .{ algorithm, key.handle, sig_view, data_view },
                zjb.Handle,
            ),
        );
    }

    /// Generates a new `CryptoKey` or `CryptoKeyPair`, returning a `Promise`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/generateKey
    pub fn generateKey(
        self: SubtleCrypto,
        algorithm: zjb.Handle,
        extractable: bool,
        key_usages: []const KeyUsage,
    ) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!algorithm.isNull());
        const usages_arr = keyUsagesToJsArray(key_usages);
        defer usages_arr.release();
        return webapi.Promise.fromHandle(
            self.handle.call(
                "generateKey",
                .{ algorithm, extractable, usages_arr },
                zjb.Handle,
            ),
        );
    }

    /// Derives a secret `CryptoKey` from `base_key`, returning a `Promise.Typed(CryptoKey)`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/deriveKey
    pub fn deriveKey(
        self: SubtleCrypto,
        algorithm: zjb.Handle,
        base_key: CryptoKey,
        derived_key_type: zjb.Handle,
        extractable: bool,
        key_usages: []const KeyUsage,
    ) webapi.Promise.Typed(CryptoKey) {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!algorithm.isNull());
        std.debug.assert(!base_key.isNull());
        std.debug.assert(!derived_key_type.isNull());
        const usages_arr = keyUsagesToJsArray(key_usages);
        defer usages_arr.release();
        return .fromHandle(
            self.handle.call(
                "deriveKey",
                .{ algorithm, base_key.handle, derived_key_type, extractable, usages_arr },
                zjb.Handle,
            ),
        );
    }

    /// Derives `length` bits from `base_key`, returning a `Promise` that resolves to an `ArrayBuffer`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/deriveBits
    pub fn deriveBits(
        self: SubtleCrypto,
        algorithm: zjb.Handle,
        base_key: CryptoKey,
        length: u32,
    ) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!algorithm.isNull());
        std.debug.assert(!base_key.isNull());
        return webapi.Promise.fromHandle(
            self.handle.call(
                "deriveBits",
                .{ algorithm, base_key.handle, @as(i32, @intCast(length)) },
                zjb.Handle,
            ),
        );
    }

    /// Imports a key from a JS handle (`ArrayBuffer`, `TypedArray`, or JWK object),
    /// returning a `Promise.Typed(CryptoKey)`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/importKey
    pub fn importKey(
        self: SubtleCrypto,
        format: KeyFormat,
        key_data: zjb.Handle,
        algorithm: zjb.Handle,
        extractable: bool,
        key_usages: []const KeyUsage,
    ) webapi.Promise.Typed(CryptoKey) {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!key_data.isNull());
        std.debug.assert(!algorithm.isNull());
        const usages_arr = keyUsagesToJsArray(key_usages);
        defer usages_arr.release();
        return .fromHandle(
            self.handle.call(
                "importKey",
                .{ webapi.constTagName(format), key_data, algorithm, extractable, usages_arr },
                zjb.Handle,
            ),
        );
    }

    /// Imports raw key bytes into a `CryptoKey`, returning a `Promise.Typed(CryptoKey)`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/importKey
    pub fn importRawKey(
        self: SubtleCrypto,
        format: KeyFormat,
        key_data: []const u8,
        algorithm: zjb.Handle,
        extractable: bool,
        key_usages: []const KeyUsage,
    ) webapi.Promise.Typed(CryptoKey) {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!algorithm.isNull());
        const view = zjb.u8ArrayView(key_data);
        defer view.release();
        return self.importKey(format, view, algorithm, extractable, key_usages);
    }

    /// Exports `key` in the requested `format`, returning a `Promise`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/exportKey
    pub fn exportKey(
        self: SubtleCrypto,
        format: KeyFormat,
        key: CryptoKey,
    ) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!key.isNull());
        return webapi.Promise.fromHandle(
            self.handle.call(
                "exportKey",
                .{ webapi.constTagName(format), key.handle },
                zjb.Handle,
            ),
        );
    }

    /// Exports and encrypts `key` using `wrapping_key` and `wrap_algorithm`,
    /// returning a `Promise` that resolves to an `ArrayBuffer`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/wrapKey
    pub fn wrapKey(
        self: SubtleCrypto,
        format: KeyFormat,
        key: CryptoKey,
        wrapping_key: CryptoKey,
        wrap_algorithm: zjb.Handle,
    ) webapi.Promise {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!key.isNull());
        std.debug.assert(!wrapping_key.isNull());
        std.debug.assert(!wrap_algorithm.isNull());
        return webapi.Promise.fromHandle(
            self.handle.call(
                "wrapKey",
                .{ webapi.constTagName(format), key.handle, wrapping_key.handle, wrap_algorithm },
                zjb.Handle,
            ),
        );
    }

    /// Decrypts and imports `wrapped_key` using `unwrapping_key`, returning a
    /// `Promise.Typed(CryptoKey)`.
    /// https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/unwrapKey
    pub fn unwrapKey(
        self: SubtleCrypto,
        format: KeyFormat,
        wrapped_key: []const u8,
        unwrapping_key: CryptoKey,
        unwrap_algorithm: zjb.Handle,
        unwrapped_key_algorithm: zjb.Handle,
        extractable: bool,
        key_usages: []const KeyUsage,
    ) webapi.Promise.Typed(CryptoKey) {
        std.debug.assert(!self.handle.isNull());
        std.debug.assert(!unwrapping_key.isNull());
        std.debug.assert(!unwrap_algorithm.isNull());
        std.debug.assert(!unwrapped_key_algorithm.isNull());
        const view = zjb.u8ArrayView(wrapped_key);
        defer view.release();
        const usages_arr = keyUsagesToJsArray(key_usages);
        defer usages_arr.release();
        return .fromHandle(
            self.handle.call(
                "unwrapKey",
                .{
                    webapi.constTagName(format),
                    view,
                    unwrapping_key.handle,
                    unwrap_algorithm,
                    unwrapped_key_algorithm,
                    extractable,
                    usages_arr,
                },
                zjb.Handle,
            ),
        );
    }
};

fn keyUsagesToJsArray(key_usages: []const KeyUsage) zjb.Handle {
    const arr = zjb.global("Array").new(.{});
    for (key_usages) |usage| {
        arr.call("push", .{webapi.constTagName(usage)}, void);
    }
    return arr;
}
