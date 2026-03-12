const moment = require('moment-timezone');

/**
 * Get current loyalty cycle string (e.g. "2026-Q2") from a date.
 * @param {Date|object} date - Date or Firestore Timestamp
 * @param {object} config - loyalty config with cycles.timezone and cycles.startMonths
 * @returns {string} e.g. "2026-Q2"
 */
function getCurrentCycle(date, config) {
  const tz = (config?.cycles?.timezone || 'Asia/Manila');
  const startMonths = config?.cycles?.startMonths || [1, 4, 7, 10];

  let d;
  if (date && typeof date.toDate === 'function') {
    d = date.toDate();
  } else if (date instanceof Date) {
    d = date;
  } else {
    d = new Date();
  }

  const m = moment(d).tz(tz);
  const year = m.year();
  const month = m.month() + 1; // moment month is 0-indexed

  let quarter = 1;
  if (month >= 10) quarter = 4;
  else if (month >= 7) quarter = 3;
  else if (month >= 4) quarter = 2;
  else quarter = 1;

  return `${year}-Q${quarter}`;
}

/**
 * Get tier name from token count based on config tiers.
 * @param {number} tokens - tokens this cycle
 * @param {object} config - loyalty config with tiers
 * @returns {string} bronze | silver | gold | diamond
 */
function getTierFromTokens(tokens, config) {
  const tiers = config?.tiers || {};
  const order = ['diamond', 'gold', 'silver', 'bronze'];

  for (const tierName of order) {
    const t = tiers[tierName];
    if (!t) continue;
    const min = (t.minTokens != null) ? Number(t.minTokens) : 0;
    const max = t.maxTokens != null ? Number(t.maxTokens) : Infinity;
    if (tokens >= min && (max === null || tokens <= max)) {
      return tierName;
    }
  }

  return 'bronze';
}

/**
 * Get cycle start and end dates for a cycle string.
 * @param {string} cycleStr - e.g. "2026-Q2"
 * @param {string} timezone - e.g. "Asia/Manila"
 * @returns {{ start: Date, end: Date }}
 */
function getCycleDateRange(cycleStr, timezone = 'Asia/Manila') {
  const match = /^(\d{4})-Q([1-4])$/.exec(cycleStr || '');
  if (!match) {
    const now = moment().tz(timezone);
    return {
      start: now.startOf('quarter').toDate(),
      end: now.endOf('quarter').toDate(),
    };
  }

  const year = parseInt(match[1], 10);
  const q = parseInt(match[2], 10);
  const startMonth = (q - 1) * 3 + 1; // Q1=1, Q2=4, Q3=7, Q4=10

  const start = moment.tz({ year, month: startMonth - 1, day: 1 }, timezone)
    .startOf('day')
    .toDate();
  const end = moment.tz({ year, month: startMonth - 1, day: 1 }, timezone)
    .add(3, 'months')
    .subtract(1, 'day')
    .endOf('day')
    .toDate();

  return { start, end };
}

/**
 * Tokens needed to reach next tier.
 * @param {number} tokens - current tokens
 * @param {object} config - loyalty config
 * @returns {{ nextTier: string|null, tokensNeeded: number }}
 */
function getTokensToNextTier(tokens, config) {
  const tiers = config?.tiers || {};
  const order = ['bronze', 'silver', 'gold', 'diamond'];
  const currentTier = getTierFromTokens(tokens, config);
  const currentIdx = order.indexOf(currentTier);
  if (currentIdx < 0 || currentIdx >= order.length - 1) {
    return { nextTier: null, tokensNeeded: 0 };
  }

  const nextTierName = order[currentIdx + 1];
  const nextTierConfig = tiers[nextTierName];
  if (!nextTierConfig) return { nextTier: null, tokensNeeded: 0 };

  const minForNext = Number(nextTierConfig.minTokens ?? 0);
  const tokensNeeded = Math.max(0, minForNext - tokens);
  return { nextTier: nextTierName, tokensNeeded };
}

module.exports = {
  getCurrentCycle,
  getTierFromTokens,
  getCycleDateRange,
  getTokensToNextTier,
};
