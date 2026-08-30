"""
prototype_motion_classifier.py

Offline prototype: 1D-CNN to classify short windows of MPU6050 accelerometer
magnitude data as NORMAL_VIBRATION vs TAMPER_ATTEMPT, as a proposed replacement
for the fixed threshold (Ta > 10.5 m/s^2) currently used in the ESP32 firmware
(see ../firmware/esp32_motion_alert.ino).

STATUS: Offline Python prototype trained and evaluated on SYNTHETIC signals
modeled after the project's real sampling rate and threshold parameters.
It has NOT been ported to the ESP32 or validated on real captured tamper
events. Next steps: log real sensor data during controlled bump-vs-tamper
tests, retrain/validate on that, then quantize and deploy on-device.
"""

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
import matplotlib.pyplot as plt
from sklearn.metrics import confusion_matrix, classification_report

SAMPLE_RATE_HZ = 20
WINDOW_SECONDS = 2.0
WINDOW_LEN = int(SAMPLE_RATE_HZ * WINDOW_SECONDS)
BASELINE_G = 9.8
THRESHOLD = 10.5


def make_synthetic_window(label: int) -> np.ndarray:
    t = np.linspace(0, WINDOW_SECONDS, WINDOW_LEN)
    noise = np.random.normal(0, 0.15, WINDOW_LEN)

    if label == 0:
        if np.random.rand() < 0.5:
            signal = BASELINE_G + noise
        else:
            spike_center = np.random.randint(10, WINDOW_LEN - 10)
            spike = 3.5 * np.exp(-0.5 * ((np.arange(WINDOW_LEN) - spike_center) / 2.0) ** 2)
            signal = BASELINE_G + spike + noise
    else:
        freq = np.random.uniform(2.0, 5.0)
        amplitude = np.random.uniform(2.0, 4.5)
        sustained = amplitude * np.abs(np.sin(2 * np.pi * freq * t))
        signal = BASELINE_G + sustained + noise

    return signal.astype(np.float32)


class VibrationDataset(Dataset):
    def __init__(self, n_samples: int):
        self.X, self.y = [], []
        for _ in range(n_samples):
            label = np.random.randint(0, 2)
            self.X.append(make_synthetic_window(label))
            self.y.append(label)
        self.X = torch.tensor(np.array(self.X)).unsqueeze(1)
        self.y = torch.tensor(np.array(self.y), dtype=torch.long)

    def __len__(self):
        return len(self.y)

    def __getitem__(self, idx):
        return self.X[idx], self.y[idx]


class TamperCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(
            nn.Conv1d(1, 8, kernel_size=5, padding=2),
            nn.ReLU(),
            nn.MaxPool1d(2),
            nn.Conv1d(8, 16, kernel_size=5, padding=2),
            nn.ReLU(),
            nn.AdaptiveAvgPool1d(1),
        )
        self.fc = nn.Linear(16, 2)

    def forward(self, x):
        x = self.net(x)
        x = x.squeeze(-1)
        return self.fc(x)


def train():
    torch.manual_seed(0)
    np.random.seed(0)

    train_ds = VibrationDataset(2000)
    val_ds = VibrationDataset(400)
    train_loader = DataLoader(train_ds, batch_size=32, shuffle=True)
    val_loader = DataLoader(val_ds, batch_size=32)

    model = TamperCNN()
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    loss_fn = nn.CrossEntropyLoss()
    history = {"train_loss": [], "val_acc": []}

    for epoch in range(15):
        model.train()
        total_loss = 0.0
        for xb, yb in train_loader:
            opt.zero_grad()
            out = model(xb)
            loss = loss_fn(out, yb)
            loss.backward()
            opt.step()
            total_loss += loss.item() * xb.size(0)

        model.eval()
        correct, total = 0, 0
        with torch.no_grad():
            for xb, yb in val_loader:
                preds = model(xb).argmax(dim=1)
                correct += (preds == yb).sum().item()
                total += yb.size(0)

        train_loss = total_loss / len(train_ds)
        val_acc = correct / total
        history["train_loss"].append(train_loss)
        history["val_acc"].append(val_acc)
        print(f"Epoch {epoch+1:2d} | train_loss={train_loss:.4f} | val_acc={val_acc:.4f}")

    return model, val_ds, history


def evaluate_and_plot(model, val_ds, history):
    model.eval()
    with torch.no_grad():
        preds = model(val_ds.X).argmax(dim=1).numpy()
    y_true = val_ds.y.numpy()

    print("\nClassification report (CNN, synthetic validation set):")
    print(classification_report(y_true, preds, target_names=["normal", "tamper"]))

    fig, ax1 = plt.subplots(figsize=(6, 4))
    ax1.plot(history["train_loss"], color="tab:red", label="train loss")
    ax1.set_xlabel("Epoch")
    ax1.set_ylabel("Train loss", color="tab:red")
    ax1.tick_params(axis="y", labelcolor="tab:red")

    ax2 = ax1.twinx()
    ax2.plot(history["val_acc"], color="tab:blue", label="val accuracy")
    ax2.set_ylabel("Validation accuracy", color="tab:blue")
    ax2.tick_params(axis="y", labelcolor="tab:blue")

    plt.title("Training curve (synthetic data)")
    fig.tight_layout()
    plt.savefig("results/training_curve.png", dpi=150)
    plt.close()

    cm = confusion_matrix(y_true, preds)
    fig, ax = plt.subplots(figsize=(4.5, 4))
    im = ax.imshow(cm, cmap="Blues")
    ax.set_xticks([0, 1])
    ax.set_yticks([0, 1])
    ax.set_xticklabels(["normal", "tamper"])
    ax.set_yticklabels(["normal", "tamper"])
    ax.set_xlabel("Predicted")
    ax.set_ylabel("True")
    ax.set_title("Confusion matrix (CNN, synthetic val set)")
    for i in range(2):
        for j in range(2):
            ax.text(j, i, cm[i, j], ha="center", va="center",
                     color="white" if cm[i, j] > cm.max() / 2 else "black")
    fig.colorbar(im)
    fig.tight_layout()
    plt.savefig("results/confusion_matrix.png", dpi=150)
    plt.close()

    return cm


def compare_against_threshold(model, n_test=500):
    model.eval()
    agree, cnn_catches_more, threshold_catches_more = 0, 0, 0
    for _ in range(n_test):
        label = np.random.randint(0, 2)
        window = make_synthetic_window(label)
        threshold_pred = int(np.max(window) > THRESHOLD)

        x = torch.tensor(window).unsqueeze(0).unsqueeze(0)
        with torch.no_grad():
            cnn_pred = model(x).argmax(dim=1).item()

        if threshold_pred == cnn_pred:
            agree += 1
        if cnn_pred == label and threshold_pred != label:
            cnn_catches_more += 1
        if threshold_pred == label and cnn_pred != label:
            threshold_catches_more += 1

    print(f"\nAgreement with existing threshold rule: {agree/n_test:.2%}")
    print(f"Cases CNN got right that threshold got wrong: {cnn_catches_more}/{n_test}")
    print(f"Cases threshold got right that CNN got wrong: {threshold_catches_more}/{n_test}")

    with open("results/threshold_comparison.txt", "w") as f:
        f.write("Comparison: 1D-CNN prototype vs existing firmware threshold rule\n")
        f.write("(synthetic data -- see README for validation status)\n\n")
        f.write(f"Test windows: {n_test}\n")
        f.write(f"Agreement with threshold rule: {agree/n_test:.2%}\n")
        f.write(f"Cases CNN correct, threshold wrong: {cnn_catches_more}/{n_test}\n")
        f.write(f"Cases threshold correct, CNN wrong: {threshold_catches_more}/{n_test}\n")


if __name__ == "__main__":
    model, val_ds, history = train()
    cm = evaluate_and_plot(model, val_ds, history)
    compare_against_threshold(model)
    torch.save(model.state_dict(), "results/tamper_cnn_prototype.pt")
    print("\nSaved results to results/")
