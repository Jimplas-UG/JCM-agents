<?php
/**
 * Plugin Name: JCM CEO Copilot (Private)
 * Description: Private CEO Copilot feature on jimplascapital.com — visible only when you are logged in as administrator.
 * Version: 1.2.0
 * Author: Jimplas Capital Management
 * License: Proprietary
 * Text Domain: jcm-ceo-copilot
 */

if (!defined('ABSPATH')) {
    exit;
}

final class JCM_Ceo_Copilot {
    private const OPTION_URL = 'jcm_mission_control_url';
    private const DEFAULT_URL = 'http://104.194.140.203:8000/mission-control';
    private const MENU_SLUG = 'jcm-ceo-copilot';

    public static function init(): void {
        add_action('admin_menu', [self::class, 'register_admin_menu']);
        add_action('admin_init', [self::class, 'register_settings']);
        add_action('admin_bar_menu', [self::class, 'admin_bar_link'], 90);
        add_action('wp_footer', [self::class, 'render_front_end_launcher']);
        add_action('template_redirect', [self::class, 'block_public_probe']);
    }

    public static function register_admin_menu(): void {
        add_menu_page(
            'CEO Copilot',
            'CEO Copilot',
            'manage_options',
            self::MENU_SLUG,
            [self::class, 'render_dashboard_page'],
            'dashicons-chart-area',
            3
        );
    }

    public static function register_settings(): void {
        register_setting('jcm_ceo_copilot', self::OPTION_URL, [
            'type'              => 'string',
            'sanitize_callback' => 'esc_url_raw',
            'default'           => self::DEFAULT_URL,
        ]);
    }

    public static function mission_control_url(): string {
        $url = get_option(self::OPTION_URL, self::DEFAULT_URL);
        return $url ?: self::DEFAULT_URL;
    }

    public static function is_https_url(string $url): bool {
        return strpos(strtolower($url), 'https://') === 0;
    }

    public static function admin_bar_link($wp_admin_bar): void {
        if (!current_user_can('manage_options')) {
            return;
        }
        $wp_admin_bar->add_node([
            'id'    => 'jcm-ceo-copilot',
            'title' => '◆ CEO Copilot',
            'href'  => self::mission_control_url(),
            'meta'  => [
                'title'  => 'Open JCM Mission Control',
                'target' => '_blank',
            ],
        ]);
    }

    /** Black & gold launcher — only visible to you on the public website when logged in. */
    public static function render_front_end_launcher(): void {
        if (!is_user_logged_in() || !current_user_can('manage_options')) {
            return;
        }

        $url = esc_url(self::mission_control_url());
        ?>
        <a
            id="jcm-ceo-copilot-launcher"
            href="<?php echo $url; ?>"
            target="_blank"
            rel="noopener noreferrer"
            aria-label="Open CEO Copilot Mission Control"
        >
            <span class="jcm-launcher-icon" aria-hidden="true">◆</span>
            <span class="jcm-launcher-text">CEO Copilot</span>
        </a>
        <style>
            #jcm-ceo-copilot-launcher {
                position: fixed;
                right: 1.25rem;
                bottom: 1.25rem;
                z-index: 99999;
                display: inline-flex;
                align-items: center;
                gap: 0.45rem;
                padding: 0.65rem 1rem;
                border-radius: 999px;
                background: linear-gradient(135deg, #0a0a0a, #111);
                border: 1px solid rgba(201, 162, 39, 0.55);
                box-shadow: 0 8px 28px rgba(0, 0, 0, 0.45), 0 0 0 1px rgba(201, 162, 39, 0.12);
                color: #e8c547;
                font: 600 0.82rem/1.2 system-ui, -apple-system, Segoe UI, sans-serif;
                letter-spacing: 0.04em;
                text-decoration: none;
                transition: transform 0.2s ease, box-shadow 0.2s ease, border-color 0.2s ease;
            }
            #jcm-ceo-copilot-launcher:hover,
            #jcm-ceo-copilot-launcher:focus {
                color: #fff8e7;
                border-color: #e8c547;
                transform: translateY(-2px);
                box-shadow: 0 12px 32px rgba(0, 0, 0, 0.5), 0 0 20px rgba(201, 162, 39, 0.18);
            }
            .jcm-launcher-icon { font-size: 0.75rem; opacity: 0.95; }
            @media (max-width: 480px) {
                #jcm-ceo-copilot-launcher {
                    right: 0.85rem;
                    bottom: 0.85rem;
                    padding: 0.55rem 0.85rem;
                }
                .jcm-launcher-text { font-size: 0.78rem; }
            }
        </style>
        <?php
    }

    public static function render_dashboard_page(): void {
        if (!current_user_can('manage_options')) {
            wp_die(esc_html__('You do not have permission to view CEO Copilot.', 'jcm-ceo-copilot'));
        }

        $url = esc_url(self::mission_control_url());
        $can_embed = self::is_https_url($url);
        ?>
        <div class="wrap jcm-ceo-copilot-wrap">
            <h1><?php echo esc_html(get_admin_page_title()); ?></h1>
            <p class="description">
                Private executive dashboard for <?php echo esc_html(parse_url(home_url(), PHP_URL_HOST) ?: 'jimplascapital.com'); ?>.
                Only you (administrator) see the CEO Copilot button on the website and this menu.
            </p>

            <div class="jcm-ceo-copilot-launch">
                <a class="button button-primary button-hero jcm-launch-btn" href="<?php echo $url; ?>" target="_blank" rel="noopener noreferrer">
                    Launch CEO Copilot
                </a>
                <p class="jcm-launch-note">
                    Opens Mission Control in a new tab. Sign in when prompted — credentials are separate from WordPress.
                </p>
            </div>

            <?php if ($can_embed) : ?>
                <div class="jcm-ceo-copilot-frame-wrap">
                    <iframe
                        title="JCM CEO Copilot Mission Control"
                        src="<?php echo $url; ?>"
                        class="jcm-ceo-copilot-frame"
                        loading="lazy"
                        referrerpolicy="no-referrer"
                        allow="fullscreen"
                    ></iframe>
                </div>
            <?php else : ?>
                <div class="notice notice-info inline jcm-mixed-content-notice">
                    <p>
                        Use <strong>Launch CEO Copilot</strong> or the gold button on your website (visible only when you are logged in).
                    </p>
                </div>
            <?php endif; ?>

            <form method="post" action="options.php" class="jcm-settings-form">
                <?php settings_fields('jcm_ceo_copilot'); ?>
                <table class="form-table" role="presentation">
                    <tr>
                        <th scope="row">
                            <label for="<?php echo esc_attr(self::OPTION_URL); ?>">Mission Control URL</label>
                        </th>
                        <td>
                            <input
                                type="url"
                                id="<?php echo esc_attr(self::OPTION_URL); ?>"
                                name="<?php echo esc_attr(self::OPTION_URL); ?>"
                                value="<?php echo esc_attr(self::mission_control_url()); ?>"
                                class="regular-text"
                            />
                        </td>
                    </tr>
                </table>
                <?php submit_button('Save URL'); ?>
            </form>
        </div>
        <style>
            .jcm-ceo-copilot-wrap { max-width: none; }
            .jcm-ceo-copilot-launch {
                background: linear-gradient(135deg, #0a0a0a, #111);
                border: 1px solid rgba(201, 162, 39, 0.35);
                border-radius: 10px;
                padding: 1.5rem 1.75rem;
                margin: 1rem 0 1.25rem;
            }
            .jcm-launch-btn {
                background: #c9a227 !important;
                border-color: #a88620 !important;
                color: #050505 !important;
                font-weight: 600;
            }
            .jcm-launch-note { margin: 0.75rem 0 0; color: #646970; }
            .jcm-ceo-copilot-frame-wrap {
                background: #050505;
                border: 1px solid rgba(201, 162, 39, 0.27);
                border-radius: 8px;
                overflow: hidden;
                min-height: calc(100vh - 320px);
                margin-bottom: 1rem;
            }
            .jcm-ceo-copilot-frame {
                width: 100%;
                min-height: calc(100vh - 320px);
                border: 0;
                display: block;
            }
        </style>
        <?php
    }

    public static function block_public_probe(): void {
        if (!is_page()) {
            return;
        }
        $slug = get_post_field('post_name', get_queried_object_id());
        if (!in_array($slug, ['ceo-copilot', 'mission-control', 'jcm-mission-control'], true)) {
            return;
        }
        if (!is_user_logged_in() || !current_user_can('manage_options')) {
            auth_redirect();
        }
    }
}

JCM_Ceo_Copilot::init();
