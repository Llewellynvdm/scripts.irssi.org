import irssi
import asyncio
import paho.mqtt.client as mqtt
import threading

__version__ = "0.1.0"

IRSSI = {
    "authors": "terminaldweller",
    "contact": "https://terminaldweller.com",
    "name": "mqtt",
    "description": "publish messages on mqtt",
    "license": "GPL3 or newer",
    "url": "https://github.com/irssi/scripts.irssi.org",
}


def on_connect(client, userdata, flags, rc):
    pass


def on_message(client, userdata, msg):
    pass


def work(client, content):
    mqtt_server = irssi.settings_get_str(b"mqtt_server")
    mqtt_port = irssi.settings_get_int(b"mqtt_port")
    mqtt_topic = irssi.settings_get_str(b"mqtt_topic")
    mqtt_pass = irssi.settings_get_str(b"mqtt_pass")
    mqtt_retain = irssi.settings_get_bool(b"mqtt_retain")
    client.username_pw_set("irssi", mqtt_pass)
    client.connect(mqtt_server, mqtt_port, 60)
    client.loop_start()
    client.publish(
        mqtt_topic.decode("utf-8"),
        content.decode("utf-8"),
        qos=0,
        retain=mqtt_retain,
    )


def publish(
    content: bytes, target: bytes, nick: bytes, server: irssi.IrcServer
) -> None:
    client = mqtt.Client(
        clean_session=True, userdata=None, protocol=mqtt.MQTTv311, transport="tcp"
    )
    client.on_connect = on_connect
    client.on_message = on_message
    mqtt_server = irssi.settings_get_str(b"mqtt_server")
    mqtt_port = irssi.settings_get_int(b"mqtt_port")
    mqtt_topic = irssi.settings_get_str(b"mqtt_topic")
    mqtt_pass = irssi.settings_get_str(b"mqtt_pass")
    mqtt_retain = irssi.settings_get_bool(b"mqtt_retain")

    threading.Thread(target=work(client, content)).start()
    # @args = ("mosquitto_pub", "-h", $MQTTServ, "-p", $MQTTPort, "-q", $MQTTQoS, "-I", $MQTTClient, "-u", $MQTTUser, "-P", $MQTTPass, "-t", $MQTTTopic,);
    # await asyncio.create_subprocess_exec(
    #     "mosquitto_pub",
    #     "-h",
    #     mqtt_server,
    #     "-p",
    #     repr(mqtt_port),
    #     "-P",
    #     mqtt_pass,
    #     "-t",
    #     mqtt_topic.decode("utf-8"),
    #     "-m",
    #     content.decode("utf-8"),
    #     stdout=asyncio.subprocess.PIPE,
    #     stderr=asyncio.subprocess.PIPE,
    # )
    # task = asyncio.create_task(work(client, content))
    # await asyncio.sleep(0)


def mqtt_sig_handler(*args, **kwargs) -> None:
    server = args[0]
    msg = args[1]
    nick = args[2]
    target = args[4]
    mqtt_server = irssi.settings_get_str(b"mqtt_server")
    if mqtt_server != "":
        publish(msg, target, nick, server)


def run_on_script_load() -> None:
    irssi.settings_add_str(
        b"misc",
        b"mqtt_server",
        b"172.17.0.1",
    )
    irssi.settings_add_int(
        b"misc",
        b"mqtt_port",
        1883,
    )
    irssi.settings_add_str(
        b"misc",
        b"mqtt_topic",
        b"test",
    )
    irssi.settings_add_str(
        b"misc",
        b"mqtt_pass",
        b"",
    )
    irssi.settings_add_bool(
        b"misc",
        b"mqtt_retain",
        False,
    )

    irssi.signal_add(b"message private", mqtt_sig_handler)


run_on_script_load()
