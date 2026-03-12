/**
 * Ash's Personality & Voice Central Module
 *
 * Ash is a friendly, helpful food assistant who:
 * - Uses first-person ("I'm Ash", "I found", "I think")
 * - Is warm and encouraging but not overly casual
 * - Adapts tone based on situation (excited for good news, empathetic for problems)
 * - Uses time-appropriate greetings
 * - Can speak in Tagalog/Tausug when preferred
 * - Signs off with a friendly closing
 */

const TimezoneUtils = require('./timezoneUtils');

class AshVoice {
  // Ash's core identity
  static get NAME() {
    return 'Ash';
  }
  static get TAGLINE() {
    return 'your Lalago food assistant';
  }

  /**
   * Get greeting by time of day in user's timezone
   */
  static getGreeting(userTimezone = 'Asia/Manila', language = 'en') {
    const hour = TimezoneUtils.getCurrentHourInUserTimezone(userTimezone);

    const greetings = {
      en: {
        morning: 'Good morning!',
        afternoon: 'Good afternoon!',
        evening: 'Good evening!',
        night: 'Hi there!',
      },
      tl: {
        morning: 'Magandang umaga!',
        afternoon: 'Magandang hapon!',
        evening: 'Magandang gabi!',
        night: 'Kumusta!',
      },
      tsg: {
        morning: 'Mayad nga aga!',
        afternoon: 'Mayad nga hapon!',
        evening: 'Mayad nga gabii!',
        night: 'Haa kamusta!',
      },
    };

    let timeOfDay;
    if (hour >= 5 && hour < 12) timeOfDay = 'morning';
    else if (hour >= 12 && hour < 18) timeOfDay = 'afternoon';
    else if (hour >= 18 && hour < 22) timeOfDay = 'evening';
    else timeOfDay = 'night';

    const lang = greetings[language] || greetings.en;
    return lang[timeOfDay] || greetings.en[timeOfDay];
  }

  /**
   * Ash's self-introduction
   */
  static introduce(firstName = null, language = 'en') {
    const namePart = firstName ? ` ${firstName}` : '';
    const tagline = AshVoice.TAGLINE;

    const intros = {
      en: `Hi${namePart}! I'm Ash, ${tagline}.`,
      tl: `Kumusta${namePart}! Ako si Ash, ang iyong ${tagline}.`,
      tsg: `Haa${namePart}! Aku hi Ash, ${tagline} mo.`,
    };

    return (intros[language] || intros.en).trim();
  }

  /**
   * Friendly sign-off
   */
  static signOff(language = 'en') {
    const signoffs = {
      en: '– Ash',
      tl: '– Ash',
      tsg: '– Ash',
    };
    return signoffs[language] || signoffs.en;
  }

  /**
   * Get notification title with Ash branding
   */
  static getTitle(baseTitle, options = {}) {
    const { includeAsh = true, emoji = true, language = 'en', type } = options;

    const emojiMap = {
      reorder: '🔄',
      recommendation: '🍽️',
      cart: '🛒',
      hunger: '🍔',
      recovery: '💳',
      order: '📦',
      chat: '💬',
    };

    const prefix = includeAsh ? 'Ash: ' : '';
    const emojiChar = emoji && type && emojiMap[type] ? emojiMap[type] + ' ' : '';
    return prefix + emojiChar + baseTitle;
  }

  /**
   * Generate notification body with Ash's voice
   */
  static getBody(baseMessage, options = {}) {
    const {
      firstName = null,
      timeUntil = null,
      isUrgent = false,
      language = 'en',
      type = 'general',
    } = options;

    let personalizedMessage = baseMessage;
    if (firstName && personalizedMessage.includes('{firstName}')) {
      personalizedMessage = personalizedMessage.replace(
        /\{firstName\}/g,
        firstName
      );
    }

    if (timeUntil != null) {
      const timePhrase = AshVoice._getTimePhrase(timeUntil, language);
      personalizedMessage = `${personalizedMessage} ${timePhrase}`;
    }

    if (isUrgent) {
      personalizedMessage = `Heads up! ${personalizedMessage}`;
    } else if (type === 'reorder') {
      personalizedMessage = `Just checking in! ${personalizedMessage}`;
    } else if (type === 'recovery') {
      personalizedMessage = `Don't worry, I've got your back! ${personalizedMessage}`;
    }

    return personalizedMessage;
  }

  /**
   * Get appropriate emoji for notification type
   */
  static getEmoji(type, variant = null) {
    const emojis = {
      reorder: { default: '🔄', success: '✅', remind: '⏰' },
      recommendation: { default: '🍽️', new: '✨', trending: '🔥' },
      cart: { default: '🛒', urgent: '⏳' },
      hunger: {
        default: '🍔',
        breakfast: '🍳',
        lunch: '🥗',
        dinner: '🍲',
      },
      recovery: { default: '💳', success: '✅', retry: '🔄' },
      order: {
        default: '📦',
        accepted: '✅',
        ready: '🍴',
        delivered: '🚚',
      },
      chat: { default: '💬', new: '💭' },
    };

    const typeEmojis = emojis[type] || { default: '🔔' };
    return typeEmojis[variant] || typeEmojis.default;
  }

  static _getTimePhrase(minutes, language) {
    const phrases = {
      en: {
        now: 'Right now!',
        soon: 'Soon!',
        minutes: (m) => `In about ${m} minutes.`,
        hour: 'In about an hour.',
        hours: (h) => `In about ${h} hours.`,
      },
    };
    const p = phrases[language] || phrases.en;

    if (minutes <= 0) return p.now;
    if (minutes < 5) return p.soon;
    if (minutes < 60) return p.minutes(Math.round(minutes));
    if (minutes < 120) return p.hour;
    return p.hours(Math.round(minutes / 60));
  }
}

module.exports = AshVoice;
