// SPDX-License-Identifier: GPL-2.0
/* Polling GT911-class touchscreen driver for Waveshare DSI panels. */
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/input.h>
#include <linux/input/mt.h>
#include <linux/input/touchscreen.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/property.h>
#include <linux/workqueue.h>
#define WS_GT911_PRODUCT_ID 0x8140
#define WS_GT911_STATUS 0x814e
#define WS_GT911_POINTS 0x814f
#define WS_GT911_MAX_CONTACTS 10
#define WS_GT911_POINT_SIZE 8
struct ws_gt911 { struct i2c_client *client; struct input_dev *input; struct touchscreen_properties prop; struct delayed_work work; struct gpio_desc *reset; unsigned int poll_ms; bool running; };
static int ws_gt911_read(struct i2c_client *c,u16 reg,void *b,size_t l){u8 a[2]={reg>>8,reg&0xff};struct i2c_msg m[2]={{.addr=c->addr,.flags=0,.len=sizeof(a),.buf=a},{.addr=c->addr,.flags=I2C_M_RD,.len=l,.buf=b}};int r=i2c_transfer(c->adapter,m,ARRAY_SIZE(m));return r==ARRAY_SIZE(m)?0:(r<0?r:-EIO);}
static int ws_gt911_write_u8(struct i2c_client *c,u16 reg,u8 v){u8 b[3]={reg>>8,reg&0xff,v};int r=i2c_master_send(c,b,sizeof(b));return r==sizeof(b)?0:(r<0?r:-EIO);}
static void ws_gt911_report(struct ws_gt911 *t,const u8 *d,unsigned int n){unsigned int i;for(i=0;i<n;i++){const u8 *p=d+i*WS_GT911_POINT_SIZE;unsigned int s=p[0]&0x0f,x=p[1]|(p[2]<<8),y=p[3]|(p[4]<<8),a=p[5]|(p[6]<<8);if(s>=WS_GT911_MAX_CONTACTS)continue;input_mt_slot(t->input,s);input_mt_report_slot_state(t->input,MT_TOOL_FINGER,true);touchscreen_report_pos(t->input,&t->prop,x,y,true);input_report_abs(t->input,ABS_MT_TOUCH_MAJOR,min(a,255U));}input_report_key(t->input,BTN_TOUCH,n!=0);input_mt_sync_frame(t->input);input_sync(t->input);}
static void ws_gt911_work(struct work_struct *w){struct ws_gt911 *t=container_of(to_delayed_work(w),struct ws_gt911,work);u8 status;u8 points[WS_GT911_MAX_CONTACTS*WS_GT911_POINT_SIZE];unsigned int n;int r;if(!READ_ONCE(t->running))return;r=ws_gt911_read(t->client,WS_GT911_STATUS,&status,sizeof(status));if(r)goto again;if(!(status&BIT(7)))goto again;n=status&0x0f;if(n>WS_GT911_MAX_CONTACTS)n=0;if(n){r=ws_gt911_read(t->client,WS_GT911_POINTS,points,n*WS_GT911_POINT_SIZE);if(r)goto clear;}ws_gt911_report(t,points,n);clear:ws_gt911_write_u8(t->client,WS_GT911_STATUS,0);again:if(READ_ONCE(t->running))schedule_delayed_work(&t->work,msecs_to_jiffies(t->poll_ms));}
static int ws_gt911_open(struct input_dev *i){struct ws_gt911 *t=input_get_drvdata(i);WRITE_ONCE(t->running,true);schedule_delayed_work(&t->work,0);return 0;} static void ws_gt911_close(struct input_dev *i){struct ws_gt911 *t=input_get_drvdata(i);WRITE_ONCE(t->running,false);cancel_delayed_work_sync(&t->work);}
static int ws_gt911_probe(struct i2c_client *c){struct ws_gt911 *t;u8 id[4]={0};u32 poll=16;int r;if(!i2c_check_functionality(c->adapter,I2C_FUNC_I2C))return -EOPNOTSUPP;t=devm_kzalloc(&c->dev,sizeof(*t),GFP_KERNEL);if(!t)return -ENOMEM;t->client=c;i2c_set_clientdata(c,t);t->reset=devm_gpiod_get_optional(&c->dev,"reset",GPIOD_OUT_LOW);if(IS_ERR(t->reset))return PTR_ERR(t->reset);if(t->reset){gpiod_set_value_cansleep(t->reset,0);msleep(20);gpiod_set_value_cansleep(t->reset,1);msleep(100);}device_property_read_u32(&c->dev,"poll-interval-ms",&poll);t->poll_ms=clamp_val(poll,5,100);r=ws_gt911_read(c,WS_GT911_PRODUCT_ID,id,sizeof(id));if(r)return r;t->input=devm_input_allocate_device(&c->dev);if(!t->input)return -ENOMEM;t->input->name="Waveshare GT911 Polling Touchscreen";t->input->id.bustype=BUS_I2C;t->input->open=ws_gt911_open;t->input->close=ws_gt911_close;input_set_drvdata(t->input,t);input_set_capability(t->input,EV_KEY,BTN_TOUCH);__set_bit(INPUT_PROP_DIRECT,t->input->propbit);input_set_abs_params(t->input,ABS_MT_POSITION_X,0,719,0,0);input_set_abs_params(t->input,ABS_MT_POSITION_Y,0,1279,0,0);input_set_abs_params(t->input,ABS_MT_TOUCH_MAJOR,0,255,0,0);touchscreen_parse_properties(t->input,true,&t->prop);r=input_mt_init_slots(t->input,WS_GT911_MAX_CONTACTS,INPUT_MT_DIRECT|INPUT_MT_DROP_UNUSED);if(r)return r;INIT_DELAYED_WORK(&t->work,ws_gt911_work);r=input_register_device(t->input);if(r)return r;dev_info(&c->dev,"GT911 touch ID '%c%c%c%c', polling %u ms\n",id[0],id[1],id[2],id[3],t->poll_ms);return 0;}
static void ws_gt911_remove(struct i2c_client *c){struct ws_gt911 *t=i2c_get_clientdata(c);WRITE_ONCE(t->running,false);cancel_delayed_work_sync(&t->work);} static const struct of_device_id ws_gt911_of_match[]={{.compatible="waveshare,gt911-poll"},{}};MODULE_DEVICE_TABLE(of,ws_gt911_of_match);
static struct i2c_driver ws_gt911_driver={.driver={.name="waveshare-gt911-poll",.of_match_table=ws_gt911_of_match},.probe=ws_gt911_probe,.remove=ws_gt911_remove};module_i2c_driver(ws_gt911_driver);
MODULE_AUTHOR("Waveshare / BeagleY-AI integration");MODULE_DESCRIPTION("Polling GT911-class touch driver for Waveshare DSI panels");MODULE_LICENSE("GPL");
