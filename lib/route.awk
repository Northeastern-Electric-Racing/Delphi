# route.awk — map one output file's `git diff -U0` hunks onto its lock segments.
#
# awk -F'\t' -v OUT=<workspace path> -v PDIR=<patch dir> -v PID=<unique id> -v UMD=<unresolved.md> \
#     [-v NEWOK=1] -f route.awk <lock rows for OUT> <diff>
#
# stdout plan rows:  patch<TAB>OUT<TAB>block<TAB>patchfile      one combined patch per block
#                    key<TAB>OUT<TAB>spec<TAB>key<TAB>value     edited name:/description: of a built skill
#                    fragment<TAB>OUT<TAB>slug<TAB>file<TAB>after   new section (NEWOK: the instruction file);
#                                                               after = preceding fragment's source, or -
#                    unresolved<TAB>OUT<TAB>reason              also written to UMD as markdown

FNR == NR { ns++; S[ns] = $2 + 0; E[ns] = $3 + 0; SRC[ns] = $4; next }
/^@@ / { flush(); header($0); inh = 1; nb = 0; next }
inh && /^[-+ ]/ { BODY[++nb] = $0; next }   # "\ No newline" lines are dropped: compiles end in one
END { flush(); emit() }

function header(s,   p, q, c) {
  split(s, p, " ")
  q = substr(p[2], 2); c = index(q, ",")
  if (c) { A = substr(q, 1, c - 1) + 0; N = substr(q, c + 1) + 0 } else { A = q + 0; N = 1 }
  q = substr(p[3], 2); c = index(q, ",")
  if (c) { M = substr(q, c + 1) + 0 } else { M = 1 }
}

function isblock(i) { return i > 0 && SRC[i] !~ /^@/ }
function seg(l,   i) { for (i = 1; i <= ns; i++) if (S[i] <= l && l <= E[i]) return i; return 0 }
function body(   k, s) { s = ""; for (k = 1; k <= nb; k++) s = s BODY[k] "\n"; return s }

function unresolved(reason) {
  print "unresolved\t" OUT "\t" reason
  printf "#### `%s` (line %d): %s\n\n```diff\n%s```\n\n", OUT, A, reason, body() >> UMD
}

function flush(   i, j, t, pos, hn) {
  if (!inh) return
  inh = 0
  if (N > 0) {
    i = seg(A); j = seg(A + N - 1)
    if (i && i == j && isblock(i) && M == 0 && A == S[i] && A + N - 1 == E[i]) {
      unresolved("deletes a whole block; to drop a block, remove it from the manifest"); return }
    if (i && i == j && isblock(i)) { t = i; pos = A - S[i] + 1 }
    else if (i && i == j && SRC[i] ~ /^@gen:.*\.skill$/) { skillkeys(i); return }
    else { unresolved("change spans segments or touches generated/separator lines"); return }
  } else if (NEWOK && fragment()) { return
  } else if (A == 0) {
    i = seg(1)
    if (isblock(i)) { t = i; pos = 0 }
    else { unresolved("insertion at the top of the file, before generated lines"); return }
  } else {
    i = seg(A); j = seg(A + 1)
    if (isblock(i) && A < E[i])        { t = i; pos = A - S[i] + 1 }   # inside a block
    else if (isblock(i) && !isblock(j)) { t = i; pos = E[i] - S[i] + 1 } # append to block
    else if (!isblock(i) && isblock(j)) { t = j; pos = 0 }               # prepend to next block
    else { unresolved(isblock(i) ? "insertion between two blocks" : "insertion inside generated/separator lines"); return }
  }
  hunk(t, pos, N, M, body())
}

function hunk(t, pos, n, m, b,   hn) { hn = ++HC[t]; HP[t, hn] = pos; HN[t, hn] = n; HM[t, hn] = m; HB[t, hn] = b }
function blank(k) { return BODY[k] ~ /^\+[ \t]*$/ }
function rng(lo, hi,   k, s) { s = ""; for (k = lo; k <= hi; k++) s = s BODY[k] "\n"; return s }

# fragment(): an insertion at a segment boundary is a new instruction fragment, except the lines
# touching a neighbouring block with no blank line between, which extend that block.
# Writes the fragment to a file and prints its row.
function fragment(   i, j, t, k, lo, hi, a, z, s, f) {
  i = seg(A); j = seg(A + 1)
  if (A > 0 && A != E[i]) return 0
  lo = 1; hi = nb
  if (isblock(i)) while (lo <= nb && !blank(lo)) lo++
  if (isblock(j)) while (hi >= 1 && !blank(hi)) hi--
  a = lo - 1; z = hi + 1                      # 1..a extends block i, z..nb extends block j
  while (lo <= hi && blank(lo)) lo++
  while (hi >= lo && blank(hi)) hi--
  if (lo > hi) return 0
  if (a) hunk(i, E[i] - S[i] + 1, 0, a, rng(1, a))
  if (z <= nb) hunk(j, 0, 0, nb - z + 1, rng(z, nb))
  for (t = ns; t > 0; t--) if (isblock(t) && E[t] <= A) break
  s = tolower(substr(BODY[lo], 2)); sub(/^[ \t]*#+/, "", s); gsub(/[^a-z0-9]+/, "-", s)
  gsub(/^-+|-+$/, "", s); s = substr(s, 1, 40); sub(/-+$/, "", s); if (s == "") s = "section"
  f = PDIR "/" PID ".f" A ".md"
  for (k = lo; k <= hi; k++) print substr(BODY[k], 2) > f
  close(f)
  print "fragment\t" OUT "\t" s "\t" f "\t" (t ? SRC[t] : "-")
  return 1
}

function skillkeys(i,   k, l, ok, key, val, spec) {
  ok = (N == M)
  for (k = 1; k <= nb; k++) if (BODY[k] !~ /^[-+](name|description): /) ok = 0
  if (!ok) { unresolved("only name: and description: of a built skill's frontmatter can be edited"); return }
  spec = substr(SRC[i], 6)
  for (k = 1; k <= nb; k++) {
    l = BODY[k]
    if (l !~ /^\+/) continue
    l = substr(l, 2); key = l; sub(/:.*/, "", key); val = l; sub(/^[^:]*: /, "", val)
    print "key\t" OUT "\t" spec "\t" key "\t" val
  }
}

function emit(   t, k, f, off, a, c, n, m) {
  for (t = 1; t <= ns; t++) {
    if (!(t in HC)) continue
    f = PDIR "/" PID "." t ".patch"
    printf "--- a/context/%s\n+++ b/context/%s\n", SRC[t], SRC[t] > f
    off = 0
    for (k = 1; k <= HC[t]; k++) {
      a = HP[t, k]; n = HN[t, k]; m = HM[t, k]
      if (n == 0) c = a + off + 1; else if (m == 0) c = a + off - 1; else c = a + off
      printf "@@ -%d,%d +%d,%d @@\n%s", a, n, c, m, HB[t, k] > f
      off += m - n
    }
    close(f)
    print "patch\t" OUT "\t" SRC[t] "\t" f
  }
}
