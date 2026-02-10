# XRAY Cloud Run (VLESS / VMESS / TROJAN)

Deploy Xray-core on Google Cloud Run with WebSocket + TLS.

## ✨ المميزات

- VLESS / VMESS / TROJAN
- UUID / Password مخصص
- WebSocket Path مخصص
- Domain مخصص (اختياري)
- Termux مدعوم
- جميع معاملات الأداء اختيارية قابلة للتخصيص

## 📋 المتطلبات

- حساب Google Cloud
- gcloud CLI مثبت
- مشروع GCP فعال

## 🚀 طرق التوزيع

### الطريقة 1: البرنامج التفاعلي (الأبسط)

```bash
git clone https://github.com/youyoulofi1-alt/yuyu-cloudrun.git
cd yuyu-cloudrun
chmod +x install.sh
./install.sh
# سيطلب منك الإعدادات تدريجياً - يمكنك الضغط Enter للتخطي
```

### الطريقة 2: البرنامج المرن مع Presets (موصى به) ⭐

```bash
chmod +x deploy-custom.sh
./deploy-custom.sh

# سيظهر لك:
# ⚡ Quick Start with Presets:
# 1) production (2048MB, 1 CPU, 16 instances, 1000 concurrency)
# 2) budget (2048MB, 2 CPU, 8 instances, 1000 concurrency)
# 3) custom (enter all settings manually)
```

### الطريقة 3: متغيرات البيئة

```bash
PROTO=vless WSPATH=/ws SERVICE=xray REGION=us-central1 \
MEMORY=512 CPU=1 MAX_INSTANCES=10 CONCURRENCY=100 \
./install.sh
```

### الطريقة 4: gcloud مباشرة

```bash
gcloud run deploy xray \
  --source . \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --memory 512Mi \
  --cpu 1
```

## ⚙️ معاملات الأداء

**جميع الخيارات اختيارية تماماً** - لا تضطر لتحديدها جميعاً:

| المعامل           | الأمثلة              | الشرح                     |
| ----------------- | -------------------- | ------------------------- |
| **Memory**        | 256, 512, 1024, 2048 | MB لكل instance           |
| **CPU**           | 0.5, 1, 2, 4         | عدد المعالجات             |
| **Timeout**       | 300, 1800, 3600      | ثواني للطلب               |
| **Max Instances** | 5, 10, 20, 50, 100   | الحد الأقصى للـ instances |
| **Concurrency**   | 50, 100, 500, 1000   | الطلبات المتزامنة         |

## 📊 الإعدادات الموصى بها

### صغير (10-100 مستخدم)

```
Memory: 256MB
CPU: 0.5
Max Instances: 5
Concurrency: 50
Cost: ~$5-10/month
```

### متوسط (100-1000 مستخدم)

```
Memory: 512MB
CPU: 1
Max Instances: 20
Concurrency: 500
Cost: ~$20-50/month
```

### كبير (1000+ مستخدم)

```
Memory: 2048MB
CPU: 2
Max Instances: 100
Concurrency: 1000
Cost: ~$100-300/month
```

## ⚡ Presets (الإعدادات المعرّفة مسبقاً)

**جديد:** اختر من presets معرّفة مسبقاً بدلاً من إدخال كل الإعدادات يدويًا!

### Production (للإنتاج)

```
Memory: 2048MB | CPU: 1 | Instances: 16 | Concurrency: 1000
```

### Budget (الميزانية المحدودة)

```
Memory: 2048MB | CPU: 2 | Instances: 8 | Concurrency: 1000
```

انظر [PRESETS.md](PRESETS.md) للتفاصيل الكاملة.

## 📚 دليل التحسين

انظر [OPTIMIZATION_GUIDE.md](OPTIMIZATION_GUIDE.md) لمزيد من التفاصيل حول:

- اختيار الإعدادات المناسبة
- مراقبة الأداء
- تكاليف Google Cloud Run
- نصائح التحسين

## 🔗 المراجع

- [Google Cloud Run Docs](https://cloud.google.com/run/docs)
- [Cloud Run Pricing](https://cloud.google.com/run/pricing)
- [Xray Docs](https://xtls.github.io)

## 💡 ملاحظات مهمة

- جميع معاملات الأداء **اختيارية** - Cloud Run سيستخدم القيم الافتراضية إذا لم تحددها
- ابدأ بإعدادات صغيرة وزد حسب الحاجة
- استخدم VLESS لأداء أفضل من VMESS
- راقب استخدام الموارد والتكاليف بانتظام

---

## 🤖 Bot Telegram — سكربتات Bash (اختصار)

هذا المشروع يتضمن سكربتات Bash لاستخدام Bot Telegram عبر polling (بدون webhook). الميزات الأساسية:

- إرسال حالة السيرفر (`status.sh`) إلى `CHAT_ID` المحدد
- الاستماع لأوامر (`bot_listener.sh`) عبر `getUpdates` (commands: `update`, `users`, `restart`, `reboot`)
- إمكانية تشغيل المستمع كخدمة systemd باستخدام ملف القالب `systemd/bot-listener.service`

الملفات المضافة:

- `scripts/status.sh` — يرسل ملخّص الحالة (IP, uptime, connected)
- `scripts/bot_listener.sh` — يستعلم `getUpdates` ويستجيب للأوامر
- `systemd/bot-listener.service` — قالب خدمة systemd

التثبيت السريع:

1. انسخ السكربتات إلى `/usr/local/bin` ومنحها صلاحيات تنفيذ:

```bash
sudo cp scripts/status.sh scripts/bot_listener.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/status.sh /usr/local/bin/bot_listener.sh
```

2. أنشئ ملف البيئة `/etc/default/yuyu_bot` وضع فيه:

```bash
# /etc/default/yuyu_bot
BOT_TOKEN="put_bot_token_here"
CHAT_ID="CHATI_D"
# اختياري: أمر لإعادة تشغيل الخدمة التي تريدها عند استقبال restart
SERVICE_RESTART_CMD="systemctl restart xray"
```

3. تثبيت jq إذا لم يكن مثبتًا:

```bash
# Debian/Ubuntu
sudo apt update && sudo apt install -y jq
# RHEL/CentOS
sudo yum install -y epel-release && sudo yum install -y jq
```

4. إنشاء وتفعيل خدمة systemd:

```bash
sudo cp systemd/bot-listener.service /etc/systemd/system/bot-listener.service
sudo systemctl daemon-reload
sudo systemctl enable --now bot-listener.service
```

أو استخدم سكربت التثبيت التلقائي (أسهل):

```bash
# شغّل سكربت التثبيت كـ root
sudo scripts/install_bot.sh
```

5. اختبار يدوياً:

```bash
# أرسل حالة الآن (مثال)
sudo BOT_TOKEN="<BOT_TOKEN>" CHAT_ID="<CHAT_ID>" /usr/local/bin/status.sh
# أو شغّل المستمع مؤقتًا (بدون systemd)
sudo BOT_TOKEN="<BOT_TOKEN>" CHAT_ID="<CHAT_ID>" /usr/local/bin/bot_listener.sh
```

أمان:

- لا تقم بنشر `BOT_TOKEN` علنًا. إذا تسرب التوكن، أعد إصداره عبر @BotFather فورًا.
- يُوصى تشغيل `bot_listener.sh` كخدمة واحدة على الخادم لتجنّب استلام التحديثات مكررة.

هل تريد أن أضبط السكربتات لتدعم مزايا إضافية (أزرار، تحقق إضافي، تفصيل اتصالات UUID)؟
