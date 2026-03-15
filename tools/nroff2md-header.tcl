#!/usr/bin/env tclsh
# nroff2md.tcl -- standalone nroff/man-page to Markdown converter
#
# Version:  0.1
# Requires: Tcl 8.6+
# Source:   https://github.com/gregnix/man-viewer
#
# Embedded modules:
#   nroffparser-0.2  -- nroff parser (AST v1)
#   ast2md-0.1       -- AST to Markdown renderer
#   debug-0.2        -- debug/trace toolkit
#
# Copyright (c) 2026 Gregor Ebbing <gregnix@github>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
# Usage:
#   tclsh nroff2md.tcl input.n                    # to stdout
#   tclsh nroff2md.tcl input.n output.md          # to file
#   tclsh nroff2md.tcl input.n -lang tcl          # code block language
#   tclsh nroff2md.tcl --batch dir/ outdir/       # batch convert
#   cat input.n | tclsh nroff2md.tcl -            # from stdin

package require Tcl 8.6-

