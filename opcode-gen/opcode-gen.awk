# Copyright (C) 2007 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Awk helper script for opcode-gen.

BEGIN {
    MAX_OPCODE = 65535;
    MAX_LIBDEX_OPCODE = 255; # TODO: Will not be true for long!
    initIndexTypes();
    initFlags();
    if (readBytecodes()) exit 1;
    deriveOpcodeChains();
    consumeUntil = "";
}

consumeUntil != "" {
    if (index($0, consumeUntil) != 0) {
        consumeUntil = "";
    } else {
        next;
    }
}

/BEGIN\(opcodes\)/ {
    consumeUntil = "END(opcodes)";
    print;

    for (i = 0; i <= MAX_OPCODE; i++) {
        if (isUnused(i) || isOptimized(i)) continue;
        printf("    public static final int %s = 0x%s;\n",
               constName[i], hex[i]);
    }

    next;
}

/BEGIN\(first-opcodes\)/ {
    consumeUntil = "END(first-opcodes)";
    print;

    for (i = 0; i <= MAX_OPCODE; i++) {
        if (isUnused(i) || isOptimized(i)) continue;
        if (isFirst[i] == "true") {
            printf("    //     DalvOps.%s\n", constName[i]);
        }
    }

    next;
}

/BEGIN\(dops\)/ {
    consumeUntil = "END(dops)";
    print;

    for (i = 0; i <= MAX_OPCODE; i++) {
        if (isUnused(i) || isOptimized(i)) continue;

        nextOp = nextOpcode[i];
        nextOp = (nextOp == -1) ? "NO_NEXT" : constName[nextOp];

        printf("    public static final Dop %s =\n" \
               "        new Dop(DalvOps.%s, DalvOps.%s,\n" \
               "            DalvOps.%s, Form%s.THE_ONE, %s,\n" \
               "            \"%s\");\n\n",
               constName[i], constName[i], family[i], nextOp, format[i],
               hasResult[i], name[i]);
    }

    next;
}

/BEGIN\(dops-init\)/ {
    consumeUntil = "END(dops-init)";
    print;

    for (i = 0; i <= MAX_OPCODE; i++) {
        if (isUnused(i) || isOptimized(i)) continue;
        printf("        set(%s);\n", constName[i]);
    }

    next;
}

/BEGIN\(libcore-opcodes\)/ {
    consumeUntil = "END(libcore-opcodes)";
    print;

    for (i = 0; i <= MAX_LIBDEX_OPCODE; i++) {
        if (isUnusedByte(i) || isOptimized(i)) continue;
        printf("    int OP_%-28s = 0x%02x;\n", constName[i], i);
    }

    next;
}

/BEGIN\(libcore-maximum-value\)/ {
    consumeUntil = "END(libcore-maximum-value)";
    print;

    # TODO: Make this smarter.
    printf("        MAXIMUM_VALUE = %d;\n", MAX_LIBDEX_OPCODE);

    next;
}

/BEGIN\(libdex-opcode-enum\)/ {
    consumeUntil = "END(libdex-opcode-enum)";
    print;

    for (i = 0; i <= MAX_LIBDEX_OPCODE; i++) {
        printf("    OP_%-28s = 0x%02x,\n", constNameOrUnusedByte(i), i);
    }

    next;
}

/BEGIN\(libdex-goto-table\)/ {
    consumeUntil = "END(libdex-goto-table)";
    print;

    for (i = 0; i <= MAX_LIBDEX_OPCODE; i++) {
        content = sprintf("        H(OP_%s),", constNameOrUnusedByte(i));
        printf("%-78s\\\n", content);
    }

    next;
}

/BEGIN\(libdex-opcode-names\)/ {
    consumeUntil = "END(libdex-opcode-names)";
    print;

    for (i = 0; i <= MAX_LIBDEX_OPCODE; i++) {
        printf("    \"%s\",\n", nameOrUnusedByte(i));
    }

    next;
}

/BEGIN\(libdex-widths\)/ {
    consumeUntil = "END(libdex-widths)";
    print;

    col = 1;
    for (i = 0; i <= MAX_LIBDEX_OPCODE; i++) {
        value = sprintf("%d,", isUnusedByte(i) ? 0 : width[i]);
        col = colPrint(value, (i == MAX_LIBDEX_OPCODE), col, 16, 2, "    ");
    }

    next;
}

/BEGIN\(libdex-flags\)/ {
    consumeUntil = "END(libdex-flags)";
    print;

    for (i = 0; i <= MAX_LIBDEX_OPCODE; i++) {
        value = flagsToC(isUnusedByte(i) ? 0 : flags[i]);
        printf("    %s,\n", value);
    }

    next;
}

/BEGIN\(libdex-formats\)/ {
    consumeUntil = "END(libdex-formats)";
    print;

    col = 1;
    for (i = 0; i <= MAX_LIBDEX_OPCODE; i++) {
        value = sprintf("kFmt%s,", isUnusedByte(i) ? "00x" : format[i]);
        col = colPrint(value, (i == MAX_LIBDEX_OPCODE), col, 7, 9, "    ");
    }

    next;
}

/BEGIN\(libdex-index-types\)/ {
    consumeUntil = "END(libdex-index-types)";
    print;

    col = 1;
    for (i = 0; i <= MAX_LIBDEX_OPCODE; i++) {
        value = isUnusedByte(i) ? "unknown" : indexType[i];
        value = sprintf("%s,", indexTypeValues[value]);
        col = colPrint(value, (i == MAX_LIBDEX_OPCODE), col, 3, 19, "    ");
    }

    next;
}

{ print; }

# Helper to print out an element in a multi-column fashion. It returns
# the (one-based) column number that the next element will be printed
# in.
function colPrint(value, isLast, col, numCols, colWidth, linePrefix) {
    isLast = (isLast || (col == numCols));
    printf("%s%-*s%s",
        (col == 1) ? linePrefix : " ",
        isLast ? 1 : colWidth, value,
        isLast ? "\n" : "");

    return (col % numCols) + 1;
}

# Read the bytecode description file.
function readBytecodes(i, parts, line, cmd, status, count) {
    # locals: parts, line, cmd, status, count
    for (;;) {
        # Read a line.
        status = getline line <bytecodeFile;
        if (status == 0) break;
        if (status < 0) {
            print "trouble reading bytecode file";
            exit 1;
        }

        # Clean up the line and extract the command.
        gsub(/  */, " ", line);
        sub(/ *#.*$/, "", line);
        sub(/ $/, "", line);
        sub(/^ /, "", line);
        count = split(line, parts);
        if (count == 0) continue; # Blank or comment line.
        cmd = parts[1];
        sub(/^[a-z][a-z]* */, "", line); # Remove the command from line.

        if (cmd == "op") {
            status = defineOpcode(line);
        } else if (cmd == "format") {
            status = defineFormat(line);
        } else {
            status = -1;
        }

        if (status != 0) {
            printf("syntax error on line: %s\n", line);
            return 1;
        }
    }

    return 0;
}

# Define an opcode.
function defineOpcode(line, count, parts, idx) {
    # locals: count, parts, idx
    count = split(line, parts);
    if (count != 6)  return -1;
    idx = parseHex(parts[1]);
    if (idx < 0) return -1;

    # Extract directly specified values from the line.
    hex[idx] = parts[1];
    name[idx] = parts[2];
    format[idx] = parts[3];
    hasResult[idx] = (parts[4] == "n") ? "false" : "true";
    indexType[idx] = parts[5];
    flags[idx] = parts[6];

    # Calculate derived values.

    constName[idx] = toupper(name[idx]);
    gsub("[---/]", "_", constName[idx]); # Dash and slash become underscore.
    gsub("[+^]", "", constName[idx]);    # Plus and caret are removed.
    split(name[idx], parts, "/");

    family[idx] = toupper(parts[1]);
    gsub("-", "_", family[idx]);         # Dash becomes underscore.
    gsub("[+^]", "", family[idx]);       # Plus and caret are removed.

    split(format[idx], parts, "");       # Width is the first format char.
    width[idx] = parts[1];

    # This association is used when computing "next" opcodes.
    familyFormat[family[idx],format[idx]] = idx;

    # Verify values.

    if (nextFormat[format[idx]] == "") {
        printf("unknown format: %s\n", format[idx]);
        return 1;
    }

    if (indexTypeValues[indexType[idx]] == "") {
        printf("unknown index type: %s\n", indexType[idx]);
        return 1;
    }

    if (flagsToC(flags[idx]) == "") {
        printf("bogus flags: %s\n", flags[idx]);
        return 1;
    }

    return 0;
}

# Define a format family.
function defineFormat(line, count, parts, i) {
    # locals: count, parts, i
    count = split(line, parts);
    if (count < 1)  return -1;
    formats[parts[1]] = line;

    parts[count + 1] = "none";
    for (i = 1; i <= count; i++) {
        nextFormat[parts[i]] = parts[i + 1];
    }

    return 0;
}

# Produce the nextOpcode and isFirst arrays. The former indicates, for
# each opcode, which one should be tried next when doing instruction
# fitting. The latter indicates which opcodes are at the head of an
# instruction fitting chain.
function deriveOpcodeChains(i, op) {
    # locals: i, op

    for (i = 0; i <= MAX_OPCODE; i++) {
        if (isUnused(i)) continue;
        isFirst[i] = "true";
    }

    for (i = 0; i <= MAX_OPCODE; i++) {
        if (isUnused(i)) continue;
        op = findNextOpcode(i);
        nextOpcode[i] = op;
        if (op != -1) {
            isFirst[op] = "false";
        }
    }
}

# Given an opcode by index, find the next opcode in the same family
# (that is, with the same base name) to try when matching instructions
# to opcodes. This simply walks the nextFormat chain looking for a
# match. This returns the index of the matching opcode or -1 if there
# is none.
function findNextOpcode(idx, fam, fmt, result) {
    # locals: fam, fmt, result
    fam = family[idx];
    fmt = format[idx];

    # Not every opcode has a version with every possible format, so
    # we have to iterate down the chain until we find one or run out of
    # formats to try.
    for (fmt = nextFormat[format[idx]]; fmt != "none"; fmt = nextFormat[fmt]) {
        result = familyFormat[fam,fmt];
        if (result != "") {
            return result;
        }
    }

    return -1;
}

# Convert a hex value to an int.
function parseHex(hex, result, chars, count, c, i) {
    # locals: result, chars, count, c, i
    hex = tolower(hex);
    count = split(hex, chars, "");
    result = 0;
    for (i = 1; i <= count; i++) {
        c = index("0123456789abcdef", chars[i]);
        if (c == 0) {
            printf("bogus hex value: %s\n", hex);
            return -1;
        }
        result = (result * 16) + c - 1;
    }
    return result;
}

# Initialize the indexTypes data.
function initIndexTypes() {
    indexTypeValues["unknown"]       = "kIndexUnknown";
    indexTypeValues["none"]          = "kIndexNone";
    indexTypeValues["varies"]        = "kIndexVaries";
    indexTypeValues["type-ref"]      = "kIndexTypeRef";
    indexTypeValues["string-ref"]    = "kIndexStringRef";
    indexTypeValues["method-ref"]    = "kIndexMethodRef";
    indexTypeValues["field-ref"]     = "kIndexFieldRef";
    indexTypeValues["inline-method"] = "kIndexInlineMethod";
    indexTypeValues["vtable-offset"] = "kIndexVtableOffset";
    indexTypeValues["field-offset"]  = "kIndexFieldOffset";
}

# Initialize the flags data.
function initFlags() {
    flagValues["branch"]        = "kInstrCanBranch";
    flagValues["continue"]      = "kInstrCanContinue";
    flagValues["switch"]        = "kInstrCanSwitch";
    flagValues["throw"]         = "kInstrCanThrow";
    flagValues["return"]        = "kInstrCanReturn";
    flagValues["invoke"]        = "kInstrInvoke";
    flagValues["optimized"]     = "0"; # Not represented in C output
    flagValues["0"]             = "0";
}

# Translate the given flags into the equivalent C expression. Returns
# "" on error.
function flagsToC(f, parts, result, i) {
    # locals: parts, result, i
    count = split(f, parts, /\|/); # Split input at pipe characters.
    result = "0";

    for (i = 1; i <= count; i++) {
        f = flagValues[parts[i]];
        if (f == "") {
            printf("bogus flag: %s\n", f);
            return ""; # Bogus flag name.
        } else if (f == "0") {
            # Nothing to append for this case.
        } else if (result == "0") {
            result = f;
        } else {
            result = result "|" f;
        }
    }

    return result;
}

# Given a packed opcode, returns the raw (unpacked) opcode value.
function unpackOpcode(idx) {
    # Note: This must be the inverse of the corresponding code in
    # libdex/DexOpcodes.h.
    if (idx <= 0xff) {
        return idx;
    } else {
        return (idx * 0x100) + 0xff;
    }
}

# Returns true if the given opcode (by index) is an "optimized" opcode.
function isOptimized(idx, parts, f) {
    # locals: parts, f
    split(flags[idx], parts, /\|/); # Split flags[idx] at pipes.
    for (f in parts) {
        if (parts[f] == "optimized") return 1;
    }
    return 0;
}

# Returns true if there is no definition for the given opcode (by index).
function isUnused(idx) {
    return (name[idx] == "");
}

# Returns true if there is no definition for the given opcode (by
# index), taken as a single-byte opcode. The odd case for this
# function is 255, which is the first extended (two-byte) opcode. For
# the purposes of this function, it is considered unused. (This is
# meant as a stop-gap measure for code that is not yet prepared to
# deal with extended opcodes.)
function isUnusedByte(idx) {
    return (idx == 255) || (name[idx] == "");
}

# Returns the constant name of the given single-byte opcode (by index)
# or the string "UNUSED_XX" (where XX is the index in hex) if the
# opcode is unused. See isUnusedByte(), above, for more info.
function constNameOrUnusedByte(idx) {
    if (isUnusedByte(idx)) {
       return toupper(sprintf("UNUSED_%02x", idx));
    }
    return constName[idx];
}

# Returns the (human-oriented) name of the given single-byte opcode
# (by index) or the string "unused-xx" (where xx is the index in hex)
# if the opcode is unused. See isUnusedByte(), above, for more info.
function nameOrUnusedByte(idx) {
    if (isUnusedByte(idx)) {
       return sprintf("unused-%02x", idx);
    }
    return name[idx];
}
