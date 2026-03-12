const moment = require('moment-timezone');

class TimezoneUtils {
  /**
   * Convert a send time (hour, minute) in user's timezone to UTC timestamp
   */
  static getScheduledTimeInUTC(userTimezone, hour, minute = 0, dayOffset = 0) {
    const tz = userTimezone || 'Asia/Manila';
    const nowInUserTz = moment().tz(tz);

    let scheduledInUserTz = moment()
      .tz(tz)
      .hour(hour)
      .minute(minute)
      .second(0)
      .millisecond(0);

    if (scheduledInUserTz.isBefore(nowInUserTz)) {
      scheduledInUserTz.add(1, 'day');
    }

    if (dayOffset > 0) {
      scheduledInUserTz.add(dayOffset, 'days');
    }

    return scheduledInUserTz.utc().toDate();
  }

  /**
   * Get current hour in user's timezone
   */
  static getCurrentHourInUserTimezone(userTimezone) {
    const tz = userTimezone || 'Asia/Manila';
    return parseInt(moment().tz(tz).format('H'), 10);
  }

  /**
   * Check if hourToCheck falls within user's quiet hours
   * @param {string} userTimezone - IANA timezone
   * @param {number} quietStart - Hour (0-23) when quiet starts
   * @param {number} quietEnd - Hour (0-23) when quiet ends
   * @param {number} hourToCheck - Hour to check (0-23)
   * @returns {boolean}
   */
  static isWithinQuietHours(userTimezone, quietStart, quietEnd, hourToCheck) {
    if (quietStart === undefined || quietEnd === undefined) return false;

    const start = Number(quietStart);
    const end = Number(quietEnd);
    const hour = Number(hourToCheck);

    if (start > end) {
      return hour >= start || hour < end;
    }
    return hour >= start && hour < end;
  }

  /**
   * Get next valid send time avoiding quiet hours
   */
  static getNextValidSendTime(
    userTimezone,
    preferredHour,
    quietStart,
    quietEnd,
  ) {
    const tz = userTimezone || 'Asia/Manila';
    let scheduledTime = this.getScheduledTimeInUTC(tz, preferredHour);

    const scheduledInUserTz = moment(scheduledTime).tz(tz);
    const scheduledHour = scheduledInUserTz.hour();

    if (
      quietStart !== undefined &&
      quietEnd !== undefined &&
      this.isWithinQuietHours(tz, quietStart, quietEnd, scheduledHour)
    ) {
      return this.getScheduledTimeInUTC(tz, preferredHour, 0, 1);
    }

    return scheduledTime;
  }
}

module.exports = TimezoneUtils;
