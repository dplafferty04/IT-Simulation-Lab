<?php
/*
 * osTicket Configuration File
 * Auto-generated for CorpTech IT Helpdesk homelab.
 * This file is bind-mounted read-only into the container.
 * After first install, osTicket writes its own version — this is a template.
 */

// Only define if not already set by the installer
if (!defined('OSTINSTALLED')) {
    define('OSTINSTALLED', true);
}

define('SECRET_SALT', getenv('INSTALL_SECRET') ?: 'Ch4ng3M3N0w!2024XYZ_UniqueSecret');
define('ADMIN_EMAIL', getenv('ADMIN_EMAIL') ?: 'admin@corp.local');
define('HELPDESK_URL', getenv('HELPDESK_URL') ?: 'http://localhost:8080');
define('HELPDESK_NAME', 'CorpTech IT Helpdesk');

// Database
define('DBHOST', getenv('MYSQL_HOST') ?: 'osticket-db');
define('DBNAME', getenv('MYSQL_DATABASE') ?: 'osticket');
define('DBUSER', getenv('MYSQL_USER') ?: 'osticket');
define('DBPASS', getenv('MYSQL_PASSWORD') ?: '');
define('DBPREFIX', 'ost_');
define('TABLE_PREFIX', 'ost_');
