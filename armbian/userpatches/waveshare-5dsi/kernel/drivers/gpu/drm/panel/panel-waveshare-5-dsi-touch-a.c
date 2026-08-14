// SPDX-License-Identifier: GPL-2.0
/* Focused Waveshare 5-DSI-TOUCH-A 720x1280 HX8394 panel driver. */
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/property.h>
#include <linux/slab.h>
#include <drm/drm_connector.h>
#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>

enum ws5_cmd_type { WS5_CMD_DCS, WS5_CMD_DELAY };
struct ws5_init_cmd { enum ws5_cmd_type type; size_t len; const u8 *data; unsigned int delay_ms; };
#define WS5_DCS(...) { .type = WS5_CMD_DCS, .len = sizeof((u8[]){ __VA_ARGS__ }), .data = (const u8[]){ __VA_ARGS__ } }
#define WS5_DELAY(_ms) { .type = WS5_CMD_DELAY, .delay_ms = (_ms) }
static const struct ws5_init_cmd ws5_init[] = {
	WS5_DCS(0xB9,0xFF,0x83,0x94),
	WS5_DCS(0xB1,0x48,0x0A,0x6A,0x09,0x33,0x54,0x71,0x71,0x2E,0x45),
	WS5_DCS(0xBA,0x61,0x03,0x68,0x6B,0xB2,0xC0),
	WS5_DCS(0xB2,0x00,0x80,0x64,0x0C,0x06,0x2F),
	WS5_DCS(0xB4,0x1C,0x78,0x1C,0x78,0x1C,0x78,0x01,0x0C,0x86,0x75,0x00,0x3F,0x1C,0x78,0x1C,0x78,0x1C,0x78,0x01,0x0C,0x86),
	WS5_DCS(0xD3,0x00,0x00,0x00,0x00,0x00,0x00,0x08,0x08,0x32,0x10,0x05,0x00,0x05,0x32,0x13,0xC1,0x00,0x01,0x32,0x10,0x08,0x00,0x00,0x37,0x03,0x07,0x07,0x37,0x05,0x05,0x37,0x0C,0x40),
	WS5_DCS(0xD5,0x18,0x18,0x18,0x18,0x22,0x23,0x20,0x21,0x04,0x05,0x06,0x07,0x00,0x01,0x02,0x03,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x19,0x19,0x19,0x19),
	WS5_DCS(0xD6,0x18,0x18,0x19,0x19,0x21,0x20,0x23,0x22,0x03,0x02,0x01,0x00,0x07,0x06,0x05,0x04,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x18,0x19,0x19,0x18,0x18),
	WS5_DCS(0xE0,0x07,0x08,0x09,0x0D,0x10,0x14,0x16,0x13,0x24,0x36,0x48,0x4A,0x58,0x6F,0x76,0x80,0x97,0xA5,0xA8,0xB5,0xC6,0x62,0x63,0x68,0x6F,0x72,0x78,0x7F,0x7F,0x00,0x02,0x08,0x0D,0x0C,0x0E,0x0F,0x10,0x24,0x36,0x48,0x4A,0x58,0x6F,0x78,0x82,0x99,0xA4,0xA0,0xB1,0xC0,0x5E,0x5E,0x64,0x6B,0x6C,0x73,0x7F,0x7F),
	WS5_DCS(0xCC,0x0B), WS5_DCS(0xC0,0x1F,0x73), WS5_DCS(0xB6,0x6B,0x6B), WS5_DCS(0xD4,0x02),
	WS5_DCS(0xBD,0x01), WS5_DCS(0xB1,0x00), WS5_DCS(0xBD,0x00), WS5_DCS(0xBF,0x40,0x81,0x50,0x00,0x1A,0xFC,0x01),
	WS5_DCS(0x11), WS5_DELAY(200), WS5_DCS(0xB2,0x00,0x80,0x64,0x0C,0x06,0x2F,0x00,0x00,0x00,0x00,0xC0,0x18), WS5_DCS(0x29), WS5_DELAY(80),
};
static const struct drm_display_mode ws5_mode = { .clock=70000,.hdisplay=720,.hsync_start=760,.hsync_end=780,.htotal=800,.vdisplay=1280,.vsync_start=1310,.vsync_end=1320,.vtotal=1324,.width_mm=62,.height_mm=110 };
struct ws5_panel { struct drm_panel panel; struct mipi_dsi_device *dsi; struct gpio_desc *reset,*iovcc,*avdd; enum drm_panel_orientation orientation; bool prepared; };
static inline struct ws5_panel *to_ws5(struct drm_panel *p){ return container_of(p,struct ws5_panel,panel); }
static int ws5_send_init(struct ws5_panel *c){ unsigned int i; int r; for(i=0;i<ARRAY_SIZE(ws5_init);i++){ const struct ws5_init_cmd *x=&ws5_init[i]; if(x->type==WS5_CMD_DELAY){msleep(x->delay_ms);continue;} r=mipi_dsi_dcs_write(c->dsi,x->data[0],x->len>1?&x->data[1]:NULL,x->len-1); if(r<0)return r;} return 0; }
static void ws5_power_off(struct ws5_panel *c){ if(c->reset){gpiod_set_value_cansleep(c->reset,0);msleep(20);} if(c->avdd){gpiod_set_value_cansleep(c->avdd,0);msleep(20);} if(c->iovcc){gpiod_set_value_cansleep(c->iovcc,0);msleep(20);} }
static int ws5_prepare(struct drm_panel *p){ struct ws5_panel *c=to_ws5(p); int r; if(c->prepared)return 0; if(c->iovcc){gpiod_set_value_cansleep(c->iovcc,1);msleep(20);} if(c->avdd){gpiod_set_value_cansleep(c->avdd,1);msleep(20);} if(c->reset){gpiod_set_value_cansleep(c->reset,0);msleep(60);gpiod_set_value_cansleep(c->reset,1);msleep(60);} r=ws5_send_init(c); if(r){ws5_power_off(c);return r;} c->prepared=true; return 0; }
static int ws5_unprepare(struct drm_panel *p){ struct ws5_panel *c=to_ws5(p); if(!c->prepared)return 0; mipi_dsi_dcs_set_display_off(c->dsi);msleep(20);mipi_dsi_dcs_enter_sleep_mode(c->dsi);msleep(120);ws5_power_off(c);c->prepared=false;return 0; }
static int ws5_get_modes(struct drm_panel *p,struct drm_connector *cn){ struct ws5_panel *c=to_ws5(p); struct drm_display_mode *m=drm_mode_duplicate(cn->dev,&ws5_mode); if(!m)return -ENOMEM; drm_mode_set_name(m);m->type=DRM_MODE_TYPE_DRIVER|DRM_MODE_TYPE_PREFERRED;drm_mode_probed_add(cn,m);cn->display_info.width_mm=m->width_mm;cn->display_info.height_mm=m->height_mm;drm_connector_set_panel_orientation(cn,c->orientation);return 1; }
static enum drm_panel_orientation ws5_get_orientation(struct drm_panel *p){return to_ws5(p)->orientation;}
static const struct drm_panel_funcs ws5_panel_funcs={.prepare=ws5_prepare,.unprepare=ws5_unprepare,.get_modes=ws5_get_modes,.get_orientation=ws5_get_orientation};
static int ws5_probe(struct mipi_dsi_device *d){ struct ws5_panel *c; unsigned long flags; int r; c=devm_kzalloc(&d->dev,sizeof(*c),GFP_KERNEL);if(!c)return -ENOMEM;c->dsi=d;mipi_dsi_set_drvdata(d,c);c->reset=devm_gpiod_get_optional(&d->dev,"reset",GPIOD_OUT_LOW);if(IS_ERR(c->reset))return PTR_ERR(c->reset);c->iovcc=devm_gpiod_get_optional(&d->dev,"iovcc",GPIOD_OUT_LOW);if(IS_ERR(c->iovcc))return PTR_ERR(c->iovcc);c->avdd=devm_gpiod_get_optional(&d->dev,"avdd",GPIOD_OUT_LOW);if(IS_ERR(c->avdd))return PTR_ERR(c->avdd);r=of_drm_get_panel_orientation(d->dev.of_node,&c->orientation);if(r)return r;drm_panel_init(&c->panel,&d->dev,&ws5_panel_funcs,DRM_MODE_CONNECTOR_DSI);c->panel.prepare_prev_first=true;r=drm_panel_of_backlight(&c->panel);if(r)return r;drm_panel_add(&c->panel);flags=MIPI_DSI_MODE_VIDEO_HSE|MIPI_DSI_MODE_VIDEO|MIPI_DSI_MODE_LPM|MIPI_DSI_CLOCK_NON_CONTINUOUS;if(device_property_read_bool(&d->dev,"waveshare,video-sync-pulse"))flags|=MIPI_DSI_MODE_VIDEO_SYNC_PULSE;if(device_property_read_bool(&d->dev,"waveshare,continuous-clock"))flags&=~MIPI_DSI_CLOCK_NON_CONTINUOUS;d->mode_flags=flags;d->format=MIPI_DSI_FMT_RGB888;d->lanes=2;r=mipi_dsi_attach(d);if(r){drm_panel_remove(&c->panel);return r;}return 0; }
static void ws5_remove(struct mipi_dsi_device *d){struct ws5_panel *c=mipi_dsi_get_drvdata(d);mipi_dsi_detach(d);drm_panel_remove(&c->panel);ws5_power_off(c);} static void ws5_shutdown(struct mipi_dsi_device *d){ws5_power_off(mipi_dsi_get_drvdata(d));}
static const struct of_device_id ws5_of_match[]={{.compatible="waveshare,5.0-dsi-touch-a"},{}};MODULE_DEVICE_TABLE(of,ws5_of_match);
static struct mipi_dsi_driver ws5_driver={.probe=ws5_probe,.remove=ws5_remove,.shutdown=ws5_shutdown,.driver={.name="panel-waveshare-5-dsi-touch-a",.of_match_table=ws5_of_match}}; module_mipi_dsi_driver(ws5_driver);
MODULE_AUTHOR("Waveshare / BeagleY-AI integration"); MODULE_DESCRIPTION("Waveshare 5-DSI-TOUCH-A MIPI-DSI panel"); MODULE_LICENSE("GPL");
