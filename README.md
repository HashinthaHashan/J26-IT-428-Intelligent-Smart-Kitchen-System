# Intelligent Smart Kitchen System Using IoT and AI/ML

<p align="center">
  <strong>SLIIT Final Year Research Project – 2026</strong>
</p>

<p align="center">
  <strong>Group ID: J26-IT-428</strong>
</p>

---

## 📌 Project Overview

**Intelligent Smart Kitchen System using IoT and AI/ML** is a final-year research project developed at the **Sri Lanka Institute of Information Technology (SLIIT)** under the **AIMS – Autonomous Intelligent Machines and Systems** research group.

The project aims to develop an intelligent, IoT-enabled kitchen platform that combines **IoT sensors, Artificial Intelligence/Machine Learning, Edge AI, computer vision, and a real-time mobile application** to improve household kitchen safety and reduce food waste.

The proposed system focuses on four major areas:

1. **LPG Gas Leak Detection, Risk Prediction, and Automated Hazard Mitigation**
2. **AI-Based Smart Pantry Food Freshness Prediction and Food Waste Reduction**
3. **AI-Based Early Detection and Prediction of Kitchen Pests**
4. **Child Safety Monitoring using Privacy-Preserving Visual Edge AI**

The four components are integrated into a unified smart kitchen platform capable of monitoring kitchen conditions, predicting potential hazards, providing early warnings, and performing automated safety actions.

---

## 🎯 Main Objective

The main objective of this research is:

> **To design, implement, and evaluate a Smart Kitchen platform that combines IoT sensors, AI risk prediction, and privacy-preserving computer vision to deliver early alerts for pests, LPG gas leaks, child hazards, and food spoilage through a single real-time mobile app.**

---

# 🔬 Research Components

## 1. LPG Gas Leak Detection, Risk Prediction, and Automated Hazard Mitigation

**Researcher:** H.R.H.H. Haparagamuwa
**Registration No:** IT23207554

This component develops an IoT and Machine Learning-based system for detecting LPG gas leaks, predicting future risk levels, and automatically reducing hazards.

### Main Features

* LPG gas leak detection using MQ-2 sensor.
* Temperature and humidity monitoring using DHT22.
* Time-series sensor data collection.
* Gas-level trend analysis.
* Machine Learning-based risk prediction.
* Four-level kitchen safety classification:

  * Safe
  * Warning
  * Dangerous
  * Critical
* Real-time alert notifications.
* Automatic exhaust fan activation.
* IoT-enabled motorized window opening.
* Integration with the central FastAPI backend and Smart Kitchen dashboard.

### Machine Learning

The system evaluates:

* Random Forest
* Logistic Regression

Feature engineering includes:

* Gas concentration
* Temperature
* Humidity
* Gas change rate
* Moving averages
* Trend indicators

The objective is to predict risk escalation rather than relying only on fixed gas thresholds.

### Novelty

The system combines **Machine Learning trend analysis**, **four-tier risk classification**, and **automated multi-action hazard mitigation** using an exhaust fan and IoT-enabled motorized window.

---

# 🍎 2. AI-Based Smart Pantry Food Freshness Prediction and Food Waste Reduction

**Researcher:** Jayasundara J.H.M.I.R.B
**Registration No:** IT23208094

This component develops an IoT and AI-based smart pantry system for monitoring non-refrigerated food and predicting food spoilage before visible signs appear.

### Target Food Items

* Bananas
* Tomatoes
* Potatoes
* Onions
* Mangoes
* Avocados

### Sensors

* MQ-135 – Air quality / VOC / CO₂-related measurements
* MQ-3 – Alcohol / ethanol detection
* DHT22 – Temperature and humidity

### Main Features

* Continuous pantry environment monitoring.
* Remaining shelf-life prediction.
* Freshness score calculation.
* Early spoilage alerts.
* AI-based recipe recommendations.
* User waste behavior learning.
* Personalized alert timing.
* Food waste and financial loss tracking.
* Mobile application dashboard.

### AI/ML

The proposed models include:

* XGBoost
* Random Forest
* Clustering / behavior learning

The system follows a four-stage prevention cycle:

```text
Predict
   ↓
Prevent
   ↓
Learn User Habits
   ↓
Reduce Food Waste
```

### Novelty

Unlike systems that simply identify whether food is fresh or rotten, this component aims to predict **remaining shelf life**, provide **preventive recipe recommendations**, and learn individual household food-waste behavior.

---

# 🪳 3. AI-Based Early Detection and Prediction of Kitchen Pests

**Researcher:** Nithis S.C.K.
**Registration No:** IT23203594

This component develops a multi-modal IoT and Edge AI system for detecting and predicting kitchen pest activity.

### Target Pests

* Rats
* Cockroaches
* Non-pest objects

### Sensors / Inputs

* Camera
* PIR sensor
* Vibration sensor
* Microphone
* Temperature sensor
* Humidity sensor

### Main Features

* Real-time pest detection.
* Multi-modal sensor fusion.
* Detection in visible and concealed areas.
* Zone-based hazard identification.
* Future infestation risk prediction.
* Edge AI processing.
* Real-time mobile notifications.

### AI/ML

A YOLO-based AI model is used to classify:

* Rats
* Cockroaches
* Non-pest objects

Sensor fusion combines camera, vibration, audio, and environmental information to improve detection accuracy and reduce false alarms.

### Novelty

The component combines **camera, vibration, audio, and environmental sensors** instead of depending on a single detection method.

It also uses **Edge AI** to improve privacy and reduce dependency on cloud processing.

---

# 👶 4. Child Safety Monitoring via Privacy-Preserving Visual Edge AI

**Researcher:** Rupasinghe D.N.A
**Registration No:** IT23388970

This component develops an on-device AI system for detecting children, identifying kitchen hazards, analyzing danger progression, and providing real-time safety alerts without transmitting raw camera footage to the cloud.

### Main Features

* Child detection.
* Kitchen hazard detection.
* Child pose estimation.
* Temporal danger analysis.
* Risk fusion.
* Real-time safety alerts.
* Edge-based processing.
* Privacy-preserving data handling.
* Real-time React dashboard.

### AI Technologies

The proposed technologies include:

* YOLOv8-nano
* YOLOv8-small
* MoveNet Lightning
* ConvLSTM
* Grounding DINO
* Bayesian risk fusion
* TensorFlow Lite INT8

### Novelty

The component introduces:

* Zero-shot unseen hazard generalization.
* Multi-modal behavioral intent decoding.
* Edge-based private wireframe masking.
* Closed-loop visual-to-IoT actuation.

The system processes visual information locally and can transmit mathematical pose information rather than raw image data.

---

# 🏗️ Overall System Architecture

The proposed system follows an integrated IoT + AI/ML architecture.

```text
                    SMART KITCHEN
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ▼                ▼                ▼
   IoT Sensors      Cameras / Edge AI   User Inputs
        │                │                │
        ▼                ▼                ▼
     ESP32          Edge Processing    Mobile App
        │                │                │
        └────────────────┼────────────────┘
                         ▼
                  FastAPI Backend
                         │
             ┌───────────┼───────────┐
             │           │           │
             ▼           ▼           ▼
          AI/ML       Database    MQTT/WebSocket
          Models         │           │
             │           │           │
             └───────────┼───────────┘
                         ▼
                 Risk / Prediction
                         │
          ┌──────────────┼──────────────┐
          │              │              │
          ▼              ▼              ▼
       Alerts       Dashboard       IoT Actions
                                     │
                           ┌─────────┴─────────┐
                           ▼                   ▼
                     Exhaust Fan        Auto Window
```

---

# 🔄 Integrated System Workflow

```text
Data Collection
       ↓
IoT / Edge Processing
       ↓
Data Preprocessing
       ↓
AI / ML Analysis
       ↓
Risk / Freshness / Pest Prediction
       ↓
Decision Making
       ↓
Real-Time Notification
       ↓
Automated Safety Action
       ↓
User Feedback
       ↓
Continuous Improvement
```

---

# 🧠 AI & Machine Learning Technologies

| Component      | Main AI/ML Technologies                                         |
| -------------- | --------------------------------------------------------------- |
| LPG Gas Safety | Random Forest, Logistic Regression                              |
| Food Freshness | XGBoost, Random Forest, Clustering                              |
| Pest Detection | YOLO-based Object Detection, Sensor Fusion, Edge AI             |
| Child Safety   | YOLOv8, MoveNet, ConvLSTM, Grounding DINO, Bayesian Risk Fusion |

---

# 🔌 IoT Technologies

The system uses IoT devices and sensors to collect real-time environmental and safety information.

### Main Hardware

* ESP32
* MQ-2 Gas Sensor
* MQ-135 Sensor
* MQ-3 Sensor
* DHT22 Sensor
* PIR Sensor
* Vibration Sensor
* Microphone
* Camera
* Relay Module
* Active Buzzer
* Exhaust Fan
* Motorized Window Actuator

---

# 💻 Software Technologies

### Backend

* Python
* FastAPI
* REST API
* MQTT
* WebSocket
* Redis

### Frontend / Mobile

* React.js
* Flutter / React Native
* Real-time dashboard

### Database

* MongoDB

### Machine Learning

* Python
* NumPy
* Pandas
* Scikit-learn
* XGBoost
* YOLO
* TensorFlow Lite

---

# 📊 Data Sources

The research uses multiple data sources.

### Sensor Data

Sensor training data is obtained from:

* Public benchmark repositories
* Kaggle
* Google Scholar / published e-nose and freshness datasets
* Controlled experimental spoilage trials

### Recipe Data

Recipe information can be obtained from public datasets such as:

* Recipe1M
* Food.com

### User Behavior Data

User behavior data is generated from anonymized household interaction records including:

* Purchase dates
* Alert responses
* Consumption
* Disposal information

---

# 🔐 Privacy and Ethical Considerations

Privacy is an important part of the proposed system.

The project focuses on:

* Processing environmental and sensor data.
* Anonymizing user interaction data.
* Avoiding storage of personally identifiable information.
* Performing child-safety visual processing at the edge where possible.
* Avoiding unnecessary transmission of raw camera footage.

The child-safety component specifically aims to process visual information locally and transmit mathematical 2D pose information rather than raw pixel data.

---

# 📱 Smart Kitchen Application

The Smart Kitchen application acts as the central user interface.

The application is expected to provide:

### Safety Monitoring

* LPG risk status
* Pest detection alerts
* Child safety alerts
* Kitchen hazard notifications

### Food Monitoring

* Freshness score
* Remaining shelf-life countdown
* Food spoilage alerts
* Recipe recommendations

### Analytics

* Food waste statistics
* Financial loss in LKR
* Weekly/monthly reports
* User behavior insights
* Shopping recommendations

---

# 📂 Repository Structure

```text
J26-IT-428-Intelligent-Smart-Kitchen-System/
│
├── docs/
│   ├── proposal/
│   ├── taf/
│   ├── research-papers/
│   └── diagrams/
│
├── hardware/
│   ├── lpg-safety/
│   ├── smart-pantry/
│   ├── pest-detection/
│   └── child-safety/
│
├── backend/
│   ├── fastapi/
│   ├── mqtt/
│   └── websocket/
│
├── frontend/
│   └── dashboard/
│
├── mobile-app/
│
├── machine-learning/
│   ├── lpg-risk-prediction/
│   ├── food-freshness/
│   ├── pest-detection/
│   └── child-safety/
│
├── datasets/
│
├── testing/
│
├── .gitignore
└── README.md
```

---

# 🌿 Sustainable Development Goals

The research contributes particularly to:

### SDG 12 – Responsible Consumption and Production

The food freshness prediction and food waste reduction component aims to reduce unnecessary household food waste.

### SDG 13 – Climate Action

Reducing food waste can contribute to reducing the environmental impact associated with wasted food and unnecessary disposal.

---

# 🧪 System Evaluation

The system will be evaluated using appropriate performance metrics for each component.

### LPG Safety

* Accuracy
* Precision
* Recall
* F1-score
* Response time
* False alarm rate
* Ventilation efficiency

### Food Freshness

* Shelf-life prediction accuracy
* Freshness prediction performance
* Alert timing
* Food waste reduction

### Pest Detection

* Accuracy
* Precision
* Recall
* F1-score
* Response time
* False alarm rate

### Child Safety

* Precision
* Recall
* F1-score
* Inference latency
* Risk prediction performance

---

# 🚀 Development Workflow

The project follows a collaborative GitHub workflow.

```text
Issue
  ↓
Create Feature Branch
  ↓
Development
  ↓
Testing
  ↓
Commit
  ↓
Push
  ↓
Pull Request
  ↓
Code Review
  ↓
Merge
```

### Branch Naming Convention

```text
feature/lpg-risk-prediction
feature/smart-pantry
feature/pest-detection
feature/child-safety
feature/backend
feature/mobile-app
feature/iot-integration
fix/sensor-data
docs/research-documentation
```

---

# 📝 Commit Message Convention

Use meaningful commit messages.

```text
feat: add LPG risk prediction model
feat: implement smart pantry monitoring
feat: add pest detection model
feat: implement child safety detection
feat: integrate ESP32 sensor data
fix: resolve sensor data processing issue
docs: update research documentation
test: add LPG detection test cases
```

---

# 👥 Research Team

| Role         | Member                       | Registration No. |
| ------------ | ---------------------------- | ---------------- |
| Group Leader | **H.R.H.H. Haparagamuwa**    | **IT23207554**   |
| Member       | **J.H.M.I.R.B. Jayasundara** | **IT23208094**   |
| Member       | **S.C.K. Nithis**            | **IT23203594**   |
| Member       | **D.N.A. Rupasinghe**        | **IT23388970**   |

---

# 🎓 Academic Information

**Institution:** Sri Lanka Institute of Information Technology (SLIIT)

**Module:** IT4010 – Research Project

**Research Group:** AIMS – Autonomous Intelligent Machines and Systems

**Specialization:** Information Technology (IT)

**Project ID:** J26-IT-428

**Project Title:** Intelligent Smart Kitchen System using IoT and AI/ML

**Academic Year:** 2026

---

# 📌 Project Status

🚧 **Research and Development in Progress**

This repository contains the source code, machine learning models, IoT implementations, datasets, documentation, experiments, and testing artifacts related to the **J26-IT-428 Intelligent Smart Kitchen System** research project.

---

## 📜 Academic Purpose

This project is developed for academic and research purposes as part of the **SLIIT IT4010 Research Project – 2026**.

All research outputs, datasets, source code, experiments, and documentation should be used responsibly and in accordance with applicable academic and ethical requirements.

---

<p align="center">
  <strong>J26-IT-428</strong>
</p>

<p align="center">
  Intelligent Smart Kitchen System using IoT and AI/ML
</p>

<p align="center">
  SLIIT – 2026
</p>
