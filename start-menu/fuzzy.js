.pragma library

// Subsequence match: every query character must appear in order. Consecutive
// runs and word-start hits score higher; shorter text wins ties. -1 = no match.
function score(query, text) {
  const q = query.toLowerCase();
  const t = text.toLowerCase();
  let qi = 0, s = 0, prev = -2;
  for (let i = 0; i < t.length && qi < q.length; i++) {
    if (t[i] !== q[qi]) continue;
    s += 1;
    if (i === prev + 1) s += 2;
    if (i === 0 || " -_./".indexOf(t[i - 1]) >= 0) s += 3;
    prev = i;
    qi++;
  }
  return qi === q.length ? s - t.length * 0.01 : -1;
}

// Filters and ranks items by fuzzy match on textOf(item). Empty query keeps order.
function filter(items, query, textOf) {
  if (query === "") return items;
  const scored = [];
  for (const it of items) {
    const sc = score(query, textOf(it));
    if (sc >= 0) scored.push({ it: it, sc: sc });
  }
  scored.sort((a, b) => b.sc - a.sc);
  return scored.map(x => x.it);
}
