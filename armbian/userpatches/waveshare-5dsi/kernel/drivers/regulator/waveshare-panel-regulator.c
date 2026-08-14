// SPDX-License-Identifier: GPL-2.0
/* Waveshare DSI panel MCU GPIO/backlight driver. */
#include <linux/backlight.h>
#include <linux/delay.h>
#include <linux/fb.h>
#include <linux/gpio/consumer.h>
#include <linux/gpio/driver.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/regmap.h>
#define WS_REG_TP 0x94
#define WS_REG_LCD 0x95
#define WS_REG_PWM 0x96
#define WS_REG_SIZE 0x97
#define WS_REG_ID 0x98
#define WS_REG_VERSION 0x99
#define WS_NUM_GPIOS 16
struct ws_panel_mcu { struct mutex lock; struct regmap *regmap; u16 output_state; u16 direction_state; struct gpio_chip gpio; struct gpio_desc *enable; };
static const struct regmap_config ws_panel_regmap={.reg_bits=8,.val_bits=8,.max_register=WS_REG_PWM};
static int ws_panel_commit(struct ws_panel_mcu *m){int r;r=regmap_write(m->regmap,WS_REG_TP,m->output_state>>8);if(r)return r;return regmap_write(m->regmap,WS_REG_LCD,m->output_state&0xff);}
static int ws_gpio_direction_input(struct gpio_chip *g,unsigned int o){struct ws_panel_mcu *m=gpiochip_get_data(g);mutex_lock(&m->lock);m->direction_state|=BIT(o);mutex_unlock(&m->lock);return 0;}
static int ws_gpio_direction_output(struct gpio_chip *g,unsigned int o,int v){struct ws_panel_mcu *m=gpiochip_get_data(g);int r;mutex_lock(&m->lock);m->direction_state&=~BIT(o);if(v)m->output_state|=BIT(o);else m->output_state&=~BIT(o);r=ws_panel_commit(m);mutex_unlock(&m->lock);return r;}
static int ws_gpio_get_direction(struct gpio_chip *g,unsigned int o){struct ws_panel_mcu *m=gpiochip_get_data(g);int d;mutex_lock(&m->lock);d=!!(m->direction_state&BIT(o));mutex_unlock(&m->lock);return d?GPIO_LINE_DIRECTION_IN:GPIO_LINE_DIRECTION_OUT;}
static int ws_gpio_get(struct gpio_chip *g,unsigned int o){struct ws_panel_mcu *m=gpiochip_get_data(g);int v;mutex_lock(&m->lock);v=!!(m->output_state&BIT(o));mutex_unlock(&m->lock);return v;}
static void ws_gpio_set(struct gpio_chip *g,unsigned int o,int v){struct ws_panel_mcu *m=gpiochip_get_data(g);if(o>=WS_NUM_GPIOS)return;mutex_lock(&m->lock);if(v)m->output_state|=BIT(o);else m->output_state&=~BIT(o);ws_panel_commit(m);mutex_unlock(&m->lock);}
static int ws_backlight_update(struct backlight_device *b){struct ws_panel_mcu *m=bl_get_data(b);int v=b->props.brightness;if(b->props.power!=FB_BLANK_UNBLANK||b->props.state&(BL_CORE_SUSPENDED|BL_CORE_FBBLANK))v=0;if(m->enable)gpiod_set_value_cansleep(m->enable,v!=0);return regmap_write(m->regmap,WS_REG_PWM,v);}
static const struct backlight_ops ws_backlight_ops={.update_status=ws_backlight_update};
static int ws_panel_raw_read(struct i2c_client *c,u8 reg,unsigned int *value){struct i2c_msg msg;u8 data;int r;msg.addr=c->addr;msg.flags=0;msg.len=1;msg.buf=&reg;r=i2c_transfer(c->adapter,&msg,1);if(r!=1)return r<0?r:-EIO;usleep_range(5000,10000);msg.flags=I2C_M_RD;msg.buf=&data;r=i2c_transfer(c->adapter,&msg,1);if(r!=1)return r<0?r:-EIO;*value=data;return 0;}
static int ws_panel_probe(struct i2c_client *c){struct backlight_properties p={};struct backlight_device *b;struct ws_panel_mcu *m;unsigned int id,size,version;int r;m=devm_kzalloc(&c->dev,sizeof(*m),GFP_KERNEL);if(!m)return -ENOMEM;mutex_init(&m->lock);i2c_set_clientdata(c,m);m->regmap=devm_regmap_init_i2c(c,&ws_panel_regmap);if(IS_ERR(m->regmap))return PTR_ERR(m->regmap);if(!ws_panel_raw_read(c,WS_REG_ID,&id))dev_info(&c->dev,"panel MCU hardware ID 0x%x\n",id);if(!ws_panel_raw_read(c,WS_REG_SIZE,&size))dev_info(&c->dev,"panel MCU size code %u\n",size);if(!ws_panel_raw_read(c,WS_REG_VERSION,&version))dev_info(&c->dev,"panel MCU firmware 0x%x\n",version);m->output_state=BIT(9)|BIT(8);r=ws_panel_commit(m);if(r)return r;msleep(20);m->gpio.parent=&c->dev;m->gpio.label=dev_name(&c->dev);m->gpio.owner=THIS_MODULE;m->gpio.base=-1;m->gpio.ngpio=WS_NUM_GPIOS;m->gpio.get=ws_gpio_get;m->gpio.set=ws_gpio_set;m->gpio.direction_input=ws_gpio_direction_input;m->gpio.direction_output=ws_gpio_direction_output;m->gpio.get_direction=ws_gpio_get_direction;m->gpio.can_sleep=true;r=devm_gpiochip_add_data(&c->dev,&m->gpio,m);if(r)return r;m->enable=devm_gpiod_get_optional(&c->dev,"enable",GPIOD_OUT_LOW);if(IS_ERR(m->enable))return PTR_ERR(m->enable);p.type=BACKLIGHT_RAW;p.max_brightness=255;p.brightness=255;b=devm_backlight_device_register(&c->dev,"waveshare-5dsi-backlight",&c->dev,m,&ws_backlight_ops,&p);if(IS_ERR(b))return PTR_ERR(b);backlight_update_status(b);return 0;}
static void ws_panel_remove(struct i2c_client *c){struct ws_panel_mcu *m=i2c_get_clientdata(c);mutex_destroy(&m->lock);} static void ws_panel_shutdown(struct i2c_client *c){struct ws_panel_mcu *m=i2c_get_clientdata(c);regmap_write(m->regmap,WS_REG_PWM,0);}
static const struct of_device_id ws_panel_of_match[]={{.compatible="waveshare,touchscreen-panel-regulator"},{}};MODULE_DEVICE_TABLE(of,ws_panel_of_match);
static struct i2c_driver ws_panel_driver={.driver={.name="waveshare-panel-mcu",.of_match_table=ws_panel_of_match},.probe=ws_panel_probe,.remove=ws_panel_remove,.shutdown=ws_panel_shutdown};module_i2c_driver(ws_panel_driver);
MODULE_AUTHOR("Waveshare / BeagleY-AI integration");MODULE_DESCRIPTION("Waveshare DSI display MCU GPIO and backlight");MODULE_LICENSE("GPL");
