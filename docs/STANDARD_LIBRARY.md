# Standard Libraries (`LibLLB` & `LibLLB_Metal`)

Low-Level Basic provides standard runtime libraries tailored for hosted applications and freestanding / bare-metal systems:

| Library | Directory | Target Type | Binary Output | Environment / Linkage |
|:---|:---|:---:|:---:|:---|
| **`LibLLB`** | `lib/hosted/` | `SharedLibrary` | `libllb.so` | **Hosted userland** runtimes (Linux / Termux / Android). Dynamically linked CRT shared object. |
| **`LibLLB_Metal`** | `lib/metal/` | `StaticLibrary` | `libllb_metal.a` | **Freestanding / bare-metal** systems (kernels, bootloaders, microcontrollers). Zero host libc dependency. |

---

## 1. Quick Comparison with C Standard Library (libc)

The following table maps LLB standard library routines to their standard C (`<string.h>`, `<stdlib.h>`, `<stdio.h>`, `<ctype.h>`, `<math.h>`) counterparts:

| LLB Module | LLB Routine | C Equivalent | Purpose & Behavior |
|:---|:---|:---|:---|
| **`Std.Strings`** | `Length(str)` | `strlen(s)` | Computes number of characters before null terminator. |
| **`Std.Strings`** | `Compare(s1, s2)` | `strcmp(s1, s2)` | Lexicographically compares two null-terminated strings (-1, 0, 1). |
| **`Std.Strings`** | `CompareN(s1, s2, n)` | `strncmp(s1, s2, n)` | Lexicographically compares up to `n` characters of two strings. |
| **`Std.Strings`** | `CompareI(s1, s2)` | `strcasecmp(s1, s2)` | Case-insensitive ASCII string comparison. |
| **`Std.Strings`** | `Copy(dest, src)` | `strcpy(dest, src)` | Copies null-terminated string to destination buffer. |
| **`Std.Strings`** | `CopyN(dest, src, n)` | `strncpy(dest, src, n)` | Copies at most `n` characters, padding with zeros. |
| **`Std.Strings`** | `Concat(dest, src)` | `strcat(dest, src)` | Appends null-terminated source string to destination. |
| **`Std.Strings`** | `SubString(src, start, n, outBuf)` | `memcpy`/slice | Extracts substring from 0-based offset into destination buffer. |
| **`Std.Strings`** | `Find(str, c)` | `strchr(s, c)` | Locates first occurrence of character byte in string. |
| **`Std.Memory`** | `Fill(dest, val, count)` | `memset(dest, val, n)` | Fills memory buffer with constant byte value. |
| **`Std.Memory`** | `SetBytes(dest, val, count)` | `memset(dest, val, n)` | Semantic alias for `Fill`. |
| **`Std.Memory`** | `Copy(dest, src, count)` | `memcpy(dest, src, n)` | Non-overlapping byte copy from source to destination. |
| **`Std.Memory`** | `CopyFast(dest, src, count)` | Aligned `memcpy` | 64-bit word-aligned chunk copy for high throughput. |
| **`Std.Memory`** | `Move(dest, src, count)` | `memmove(dest, src, n)`| Overlap-safe memory copy. |
| **`Std.Memory`** | `Compare(p1, p2, count)` | `memcmp(p1, p2, n)` | Byte-by-byte memory comparison (-1, 0, 1). |
| **`Std.Memory`** | `Search(ptr, val, count)` | `memchr(s, c, n)` | Locates first matching byte within `count` bytes of memory. |
| **`Format`** | `SprintF(outBuf, maxLen, fmt, args...)` | `snprintf(buf, size, fmt, ...)` | Safe variadic string formatting (`%s`, `%u`, `%d`/`%i`, `%x`/`%X`, `%c`, `%%`). |
| **`Format`** | `ToHex(val, outBuf, prefix)` | `sprintf(buf, "%x", val)` | Unsigned integer to hexadecimal string conversion. |
| **`Format`** | `ToUInt(val, outBuf)` | `sprintf(buf, "%llu", val)` | Unsigned integer to decimal string conversion. |
| **`Format`** | `ToInt(val, outBuf)` | `sprintf(buf, "%lld", val)` | Signed integer to decimal string conversion. |
| **`Conv`** | `ParseUInt(str)` | `strtoull(str, NULL, 10)` | Parses unsigned decimal number from ASCII string. |
| **`Conv`** | `ParseInt(str)` | `strtoll(str, NULL, 10)` | Parses signed decimal number from ASCII string. |
| **`Conv`** | `ParseHex(str)` | `strtoull(str, NULL, 16)` | Parses hexadecimal integer from ASCII string. |
| **`Math`** | `Abs(val)` | `labs(x)` / `llabs(x)` | Absolute value of signed 64-bit integer. |
| **`Math`** | `Min(a, b)` | `MIN(a, b)` | Minimum of two signed 64-bit integers. |
| **`Math`** | `Max(a, b)` | `MAX(a, b)` | Maximum of two signed 64-bit integers. |
| **`Math`** | `Clamp(val, low, high)` | `__builtin_clamp` | Clamps value within inclusive range `[lowVal, highVal]`. |
| **`Math`** | `DivRoundUp(num, denom)` | `(num + denom - 1) / denom` | Ceiled integer division. |
| **`Math`** | `AlignUp(val, align)` | `(val + align - 1) & ~(align - 1)` | Aligns address upwards to power-of-two boundary. |
| **`Math`** | `PopCount(val)` | `__builtin_popcountll(x)` | Counts number of set bits (1s) in 64-bit integer. |
| **`Math`** | `CountLeadingZeros(val)` | `__builtin_clzll(x)` | Counts leading zero bits (0 to 64). |
| **`Math`** | `CountTrailingZeros(val)`| `__builtin_ctzll(x)` | Counts trailing zero bits (0 to 64). |
| **`Ascii`** | `IsDigit(c)` | `isdigit(c)` | Checks if ASCII byte is `'0'` through `'9'`. |
| **`Ascii`** | `IsAlpha(c)` | `isalpha(c)` | Checks if ASCII byte is `'A'`-`'Z'` or `'a'`-`'z'`. |
| **`Ascii`** | `IsAlnum(c)` | `isalnum(c)` | Checks if ASCII byte is alphanumeric. |
| **`Ascii`** | `IsWhitespace(c)` | `isspace(c)` | Checks if ASCII byte is space, tab, newline, or carriage return. |
| **`Ascii`** | `IsHexDigit(c)` | `isxdigit(c)` | Checks if ASCII byte is valid hexadecimal character. |
| **`Ascii`** | `ToUpper(c)` | `toupper(c)` | Converts lowercase ASCII character to uppercase. |
| **`Ascii`** | `ToLower(c)` | `tolower(c)` | Converts uppercase ASCII character to lowercase. |
| **`TextWriter`** | `PrintF(fmt, args...)` | `fprintf(stream, fmt, ...)` | Variadic stream formatting attached to any `ICharSink` destination. |

---

## 2. API Reference & Signatures

### Module `Std.Strings`

```vb
' Computes length of null-terminated string (excluding null terminator)
Public Unsafe Function Length(ByVal str As Pointer To Byte) As UInt64

' Lexicographically compares two null-terminated strings
' Returns: 0 if equal, -1 if s1 < s2, 1 if s1 > s2
Public Unsafe Function Compare(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte) As Int32

' Lexicographically compares at most n characters of two strings
Public Unsafe Function CompareN(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte, ByVal n As UInt64) As Int32

' Case-insensitive string comparison
Public Unsafe Function CompareI(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte) As Int32

' Copies null-terminated string from src to dest
Public Unsafe Function Copy(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte) As UInt64

' Copies at most n characters from src to dest, zero-filling the remainder
Public Unsafe Function CopyN(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal n As UInt64) As UInt64

' Appends null-terminated src string to dest buffer
Public Unsafe Function Concat(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte) As UInt64

' Extracts substring from 0-based offset into outBuf
Public Unsafe Function SubString(ByVal src As Pointer To Byte, ByVal start As UInt64, ByVal count As UInt64, ByVal outBuf As Pointer To Byte) As UInt64

' Finds first occurrence of character c in str
Public Unsafe Function Find(ByVal str As Pointer To Byte, ByVal c As Byte) As Pointer To Byte
```

---

### Module `Std.Memory`

```vb
' Fills count bytes with constant byte value
Public Unsafe Sub Fill(ByVal dest As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64)

' Semantic alias for Fill
Public Unsafe Sub SetBytes(ByVal dest As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64)

' Fast non-overlapping byte copy
Public Unsafe Sub Copy(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64)

' High-throughput 64-bit word-aligned chunk copy
Public Unsafe Sub CopyFast(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64)

' Safe copy handling overlapping memory regions
Public Unsafe Sub Move(ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte, ByVal count As UInt64)

' Compares first count bytes of two memory buffers
' Returns: 0 if equal, -1 if s1 < s2, 1 if s1 > s2
Public Unsafe Function Compare(ByVal s1 As Pointer To Byte, ByVal s2 As Pointer To Byte, ByVal count As UInt64) As Int32

' Searches first count bytes for value val; returns pointer to matched byte or 0
Public Unsafe Function Search(ByVal ptr As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64) As Pointer To Byte
```

---

### Module `Format`

```vb
' Converts unsigned integer to hexadecimal string
Public Unsafe Function ToHex(ByVal value As UInt64, ByVal outBuf As Pointer To Byte, ByVal prefix As Boolean) As UInt32

' Converts unsigned integer to decimal string
Public Unsafe Function ToUInt(ByVal value As UInt64, ByVal outBuf As Pointer To Byte) As UInt32

' Converts signed integer to decimal string
Public Unsafe Function ToInt(ByVal value As Int64, ByVal outBuf As Pointer To Byte) As UInt32

' Safe variadic formatted printing into bounded buffer
' Supported specifiers: %s (string), %u (uint64), %d / %i (int64), %x / %X (hex), %c (char), %% (literal %)
Public Unsafe Function SprintF(ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt64, ByVal fmt As Pointer To Byte, ParamArray args() As Pointer To Int64) As UInt32
```

---

### Module `Conv`

```vb
' Parses ASCII decimal string into unsigned 64-bit integer
Public Unsafe Function ParseUInt(ByVal str As Pointer To Byte) As UInt64

' Parses ASCII decimal string (with optional +/-) into signed 64-bit integer
Public Unsafe Function ParseInt(ByVal str As Pointer To Byte) As Int64

' Parses ASCII hexadecimal string (with optional 0x / 0X / &H prefix) into unsigned 64-bit integer
Public Unsafe Function ParseHex(ByVal str As Pointer To Byte) As UInt64
```

---

### Module `Math`

```vb
' Computes absolute value of signed 64-bit integer
Public Function Abs(ByVal val As Int64) As Int64

' Returns minimum of two signed 64-bit integers
Public Function Min(ByVal a As Int64, ByVal b As Int64) As Int64

' Returns maximum of two signed 64-bit integers
Public Function Max(ByVal a As Int64, ByVal b As Int64) As Int64

' Clamps value within [lowVal, highVal]
Public Function Clamp(ByVal val As Int64, ByVal lowVal As Int64, ByVal highVal As Int64) As Int64

' Ceiled division: (numerator + denominator - 1) / denominator
Public Function DivRoundUp(ByVal numerator As UInt64, ByVal denominator As UInt64) As UInt64

' Aligns value upwards to power-of-two alignment boundary
Public Function AlignUp(ByVal value As UInt64, ByVal alignment As UInt64) As UInt64

' Counts number of 1 bits in 64-bit integer
Public Function PopCount(ByVal value As UInt64) As UInt32

' Counts number of leading zero bits
Public Function CountLeadingZeros(ByVal value As UInt64) As UInt32

' Counts number of trailing zero bits
Public Function CountTrailingZeros(ByVal value As UInt64) As UInt32
```

---

### Module `Ascii`

```vb
Public Function IsDigit(ByVal c As Byte) As Boolean
Public Function IsAlpha(ByVal c As Byte) As Boolean
Public Function IsAlnum(ByVal c As Byte) As Boolean
Public Function IsWhitespace(ByVal c As Byte) As Boolean
Public Function IsHexDigit(ByVal c As Byte) As Boolean
Public Function ToUpper(ByVal c As Byte) As Byte
Public Function ToLower(ByVal c As Byte) As Byte
```

---

### Class `TextWriter` & Interface `ICharSink`

```vb
' Interface for stream destination drivers (Serial, VGA console, file descriptors)
Public Interface ICharSink
    Sub WriteChar(ByVal c As Byte)
    Sub WriteString(ByVal str As Pointer To Byte)
End Interface

' Stream writer class wrapping any ICharSink implementation
Public Class TextWriter
    Public Unsafe Sub Attach(ByVal sink As Pointer To ICharSink)
    Public Unsafe Sub WriteChar(ByVal c As Byte)
    Public Unsafe Sub Write(ByVal str As Pointer To Byte)
    Public Unsafe Sub WriteLine(ByVal str As Pointer To Byte)
    Public Unsafe Sub WriteUInt(ByVal value As UInt64)
    Public Unsafe Sub WriteInt(ByVal value As Int64)
    Public Unsafe Sub WriteHex(ByVal value As UInt64, ByVal prefix As Boolean)
    Public Unsafe Sub PrintF(ByVal fmt As Pointer To Byte, ParamArray args() As Pointer To Int64)
End Class
```

---

## 3. How to Use in Projects

### Hosted Applications (Dynamic Shared Library)

Add the shared library path to `Libraries` in your project manifest:

```ini
[Project]
Name = "MyApp"
Type = "Executable"

[Target]
Platform = "hosted"

[Linker]
Libraries = [
    "../../lib/hosted/build/libllb.so"
]
```

Declare routines with `Lib "libllb"`:
```vb
Public Declare Function SprintF Lib "libllb" (ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt64, ByVal fmt As Pointer To Byte, ParamArray args() As Pointer To Int64) As UInt32
Public Declare Function Std_Strings_Concat Lib "libllb" (ByVal dest As Pointer To Byte, ByVal src As Pointer To Byte) As UInt64
```

### Freestanding & Bare-Metal Kernels (Static Archive)

Add the static library archive to `Libraries` in your project manifest:

```ini
[Project]
Name = "Kernel"
Type = "Kernel"

[Target]
Architecture = "x86_64-unknown-none-elf"
Platform     = "freestanding"

[Linker]
Libraries = [
    "../../lib/metal/build/libllb_metal.a"
]
```

Declare routines with `Lib "libllb_metal"`:
```vb
Public Declare Function Min Lib "libllb_metal" (ByVal a As Int64, ByVal b As Int64) As Int64
Public Declare Function Std_Memory_Search Lib "libllb_metal" (ByVal ptr As Pointer To Byte, ByVal val As Byte, ByVal count As UInt64) As Pointer To Byte
Public Declare Function SprintF Lib "libllb_metal" (ByVal outBuf As Pointer To Byte, ByVal maxLen As UInt64, ByVal fmt As Pointer To Byte, ParamArray args() As Pointer To Int64) As UInt32
```
