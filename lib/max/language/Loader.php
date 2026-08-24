<?php

/*
+---------------------------------------------------------------------------+
| Revive Adserver                                                           |
| http://www.revive-adserver.com                                            |
|                                                                           |
| Copyright: See the COPYRIGHT.txt file.                                    |
| License: GPLv2 or later, see the LICENSE.txt file.                        |
+---------------------------------------------------------------------------+
*/

require_once MAX_PATH . '/lib/RV/Admin/Languages.php';

/**
 * @package    MaxUI
 * @subpackage Language
 */

/**
 * A class that can be used to load the necessary language file(s) for
 * selected part of system.
 *
 * @static
 */
class Language_Loader
{
    private static array $aLastLoaded = [];

    /**
     * The method to load the selected language file.
     *
     * Section should to be a name of requested language file excluding the .lang.php extension.
     * Lang is a name of directory with language files
     *
     * @param string $section section of the system
     * @param string $lang  language symbol
     */
    public static function load($section = 'default', $lang = null)
    {
        if (!defined('phpAds_dbmsname')) {
            define('phpAds_dbmsname', '');
        }
        $aConf = $GLOBALS['_MAX']['CONF'];
        if (!empty($GLOBALS['_MAX']['PREF'])) {
            $aPref = $GLOBALS['_MAX']['PREF'];
        } else {
            $aPref = [];
        }
        if (is_null($lang) && !empty($aPref['language'])) {
            $lang = $aPref['language'];
        }

        // Always load the English language, in case of incomplete translations
        if (!self::loadLanguage($section, 'en')) {
            return;
        }

        // Load the language from preferences, if possible, otherwise load
        // the global preference, if possible
        // If language preference is set, do not load language from config file (common bug here is to check if prefereced language is 'en'!)
        if (!empty($lang) && preg_match('#^[a-z][a-z](_[A-Z][A-Z])?$#', $lang)) {
            self::loadLanguage($section, $lang);
        } else {
            // Check if using full language name (polish), if so then set to use two letter abbr (pl).
            if (!empty($aConf['max']['language'])) {
                $confMaxLanguage = $aConf['max']['language'];
                if (isset(RV_Admin_Languages::$aOldLanguagesMap[$confMaxLanguage])) {
                    $confMaxLanguage = RV_Admin_Languages::$aOldLanguagesMap[$confMaxLanguage];
                }
            }

            if (!empty($confMaxLanguage)) {
                self::loadLanguage($section, $confMaxLanguage);
            }
        }
    }

    private static function loadLanguage($section, $lang): bool
    {
        if ($lang === (self::$aLastLoaded[$section] ?? null)) {
            return true;
        }

        $path = MAX_PATH . '/lib/max/language/' . $lang . '/' . $section . '.lang.php';

        if (!file_exists($path)) {
            return false;
        }

        $PRODUCT_NAME = PRODUCT_NAME;
        $PRODUCT_URL = PRODUCT_URL;
        $PRODUCT_DOCSURL = PRODUCT_DOCSURL;
        $phpAds_dbmsname = phpAds_dbmsname;

        include $path;

        self::$aLastLoaded[$section] = $lang;

        return true;
    }
}
