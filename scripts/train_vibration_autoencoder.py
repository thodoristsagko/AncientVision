#!/usr/bin/env python3
"""
AncientVision Vibration Anomaly Detection - Autoencoder Training Pipeline v3.0

This script trains an autoencoder neural network on "normal" vibration data
collected from the AncientVision sensor system. The trained model is then
converted to TensorFlow Lite format for deployment in the Flutter app.

v3.0 Architecture: 7 -> 6 (ReLU) -> 4 (ReLU) -> 3 (bottleneck) -> 4 (ReLU) -> 6 (ReLU) -> 7 (linear)
Input features per window: [rms, ppv, freq, crest, cent, kurt, stalta]

Usage:
  1. Collect normal vibration data using the AncientVision app (10-30 min)
  2. Export sensor_data from Firebase to CSV or use the BLE monitor script
  3. Run: python train_vibration_autoencoder.py --input data.csv
  4. Output: vibration_anomaly.tflite (deploy to Flutter assets/ml/)

Requirements:
  pip install tensorflow numpy pandas scikit-learn

References:
  - DIN 4150-3:1999 (heritage structure vibration limits)
  - ShawnHymel/tinyml-example-anomaly-detection (pipeline reference)
  - CWRU Bearing Dataset (transfer learning benchmark)
"""

import argparse
import json
import os
import sys
import numpy as np
import pandas as pd
from pathlib import Path

try:
    import tensorflow as tf
    from tensorflow import keras
    from sklearn.preprocessing import StandardScaler
    from sklearn.model_selection import train_test_split
except ImportError:
    print("Missing dependencies. Install with:")
    print("  pip install tensorflow numpy pandas scikit-learn")
    sys.exit(1)


# v3.0 feature names (7 features from firmware v3.0)
FEATURE_NAMES = ['rms', 'ppv', 'freq', 'crest', 'cent', 'kurt', 'stalta']

# Default thresholds for anomaly detection (will be calibrated from data)
DEFAULT_THRESHOLD_PERCENTILE = 95  # 95th percentile of reconstruction error


def load_csv_data(filepath: str) -> pd.DataFrame:
    """Load vibration feature data from CSV file."""
    df = pd.read_csv(filepath)

    # Check for required columns
    available = [f for f in FEATURE_NAMES if f in df.columns]
    if len(available) < 4:
        print(f"Error: CSV must contain at least 4 of {FEATURE_NAMES}")
        print(f"Found columns: {list(df.columns)}")
        sys.exit(1)

    print(f"Loaded {len(df)} samples with features: {available}")
    return df[available]


def load_json_data(filepath: str) -> pd.DataFrame:
    """Load vibration feature data from JSON lines file."""
    records = []
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                records.append(record)
            except json.JSONDecodeError:
                continue

    df = pd.DataFrame(records)
    available = [f for f in FEATURE_NAMES if f in df.columns]
    if len(available) < 4:
        print(f"Error: JSON must contain at least 4 of {FEATURE_NAMES}")
        sys.exit(1)

    print(f"Loaded {len(df)} samples with features: {available}")
    return df[available]


def generate_synthetic_normal_data(n_samples: int = 2000) -> pd.DataFrame:
    """
    Generate synthetic 'normal' vibration data for initial model training.
    Based on typical archaeological site ambient vibration profiles.

    v3.0: Includes centroid, kurtosis, and STA/LTA ratio.
    """
    np.random.seed(42)

    # Normal ambient vibration (majority of data)
    n_ambient = int(n_samples * 0.7)
    ambient = {
        'rms': np.random.lognormal(-5.5, 0.5, n_ambient).clip(0.0005, 0.02),
        'ppv': np.random.lognormal(-2.5, 0.6, n_ambient).clip(0.01, 0.3),
        'freq': np.random.normal(3.0, 1.5, n_ambient).clip(0.5, 8.0),
        'crest': np.random.normal(2.0, 0.5, n_ambient).clip(1.1, 4.0),
        'cent': np.random.normal(5.0, 1.5, n_ambient).clip(2.0, 8.0),
        'kurt': np.random.normal(0.5, 0.5, n_ambient).clip(-0.5, 1.5),
        'stalta': np.random.normal(1.0, 0.25, n_ambient).clip(0.5, 1.5),
    }

    # Footstep vibration (periodic, low freq)
    n_footsteps = int(n_samples * 0.2)
    footsteps = {
        'rms': np.random.lognormal(-4.5, 0.4, n_footsteps).clip(0.005, 0.03),
        'ppv': np.random.lognormal(-1.5, 0.4, n_footsteps).clip(0.05, 0.5),
        'freq': np.random.normal(2.5, 0.8, n_footsteps).clip(1.0, 5.0),
        'crest': np.random.normal(2.5, 0.6, n_footsteps).clip(1.5, 4.5),
        'cent': np.random.normal(3.0, 1.0, n_footsteps).clip(1.0, 5.0),
        'kurt': np.random.normal(1.5, 0.8, n_footsteps).clip(0.0, 3.0),
        'stalta': np.random.normal(1.5, 0.4, n_footsteps).clip(1.0, 2.5),
    }

    # Light tool use (hand tools, brushing)
    n_tools = int(n_samples * 0.1)
    tools = {
        'rms': np.random.lognormal(-4.0, 0.5, n_tools).clip(0.005, 0.05),
        'ppv': np.random.lognormal(-1.0, 0.5, n_tools).clip(0.1, 0.8),
        'freq': np.random.normal(8.0, 3.0, n_tools).clip(3.0, 20.0),
        'crest': np.random.normal(3.0, 0.8, n_tools).clip(1.5, 5.0),
        'cent': np.random.normal(12.0, 4.0, n_tools).clip(5.0, 25.0),
        'kurt': np.random.normal(1.5, 1.0, n_tools).clip(0.5, 4.0),
        'stalta': np.random.normal(2.0, 0.5, n_tools).clip(1.5, 3.0),
    }

    # Combine
    data = {}
    for key in FEATURE_NAMES:
        data[key] = np.concatenate([ambient[key], footsteps[key], tools[key]])

    df = pd.DataFrame(data)
    # Shuffle
    df = df.sample(frac=1.0, random_state=42).reset_index(drop=True)

    print(f"Generated {len(df)} synthetic normal samples")
    print(f"Feature ranges:")
    for col in FEATURE_NAMES:
        print(f"  {col}: {df[col].min():.4f} - {df[col].max():.4f} (mean: {df[col].mean():.4f})")

    return df


def build_autoencoder(input_dim: int) -> keras.Model:
    """
    Build deeper autoencoder for vibration anomaly detection (v3.0).

    Architecture: input_dim -> 6 (ReLU) -> 4 (ReLU) -> 3 (bottleneck)
                  -> 4 (ReLU) -> 6 (ReLU) -> input_dim (linear)

    The deeper architecture with 7:3 bottleneck ratio (57% compression)
    provides better anomaly discrimination than the v2.0 4:3 architecture.
    """
    encoder_input = keras.layers.Input(shape=(input_dim,), name='encoder_input')

    # Encoder
    x = keras.layers.Dense(6, activation='relu', name='enc_dense1')(encoder_input)
    x = keras.layers.Dense(4, activation='relu', name='enc_dense2')(x)
    x = keras.layers.Dense(3, activation='relu', name='bottleneck')(x)

    # Decoder
    x = keras.layers.Dense(4, activation='relu', name='dec_dense1')(x)
    x = keras.layers.Dense(6, activation='relu', name='dec_dense2')(x)
    decoder_output = keras.layers.Dense(input_dim, activation='linear', name='decoder_output')(x)

    model = keras.Model(encoder_input, decoder_output, name='vibration_autoencoder_v3')

    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=0.001),
        loss='mse',
    )

    return model


def train_model(model: keras.Model, X_train: np.ndarray, X_val: np.ndarray,
                epochs: int = 200, batch_size: int = 32) -> keras.callbacks.History:
    """Train the autoencoder on normal vibration data."""

    callbacks = [
        keras.callbacks.EarlyStopping(
            monitor='val_loss',
            patience=20,
            restore_best_weights=True,
        ),
        keras.callbacks.ReduceLROnPlateau(
            monitor='val_loss',
            factor=0.5,
            patience=10,
            min_lr=1e-6,
        ),
    ]

    history = model.fit(
        X_train, X_train,  # Autoencoder: input = target
        validation_data=(X_val, X_val),
        epochs=epochs,
        batch_size=batch_size,
        callbacks=callbacks,
        verbose=1,
    )

    return history


def compute_thresholds(model: keras.Model, X_data: np.ndarray,
                       percentile: float = 95) -> dict:
    """
    Compute anomaly detection thresholds from reconstruction errors
    on normal training data.
    """
    predictions = model.predict(X_data, verbose=0)
    mse_per_sample = np.mean((X_data - predictions) ** 2, axis=1)

    threshold_low = np.percentile(mse_per_sample, percentile)
    threshold_high = np.percentile(mse_per_sample, 99)

    print(f"\nReconstruction Error Statistics (normal data):")
    print(f"  Mean:   {np.mean(mse_per_sample):.6f}")
    print(f"  Std:    {np.std(mse_per_sample):.6f}")
    print(f"  Median: {np.median(mse_per_sample):.6f}")
    print(f"  P95:    {threshold_low:.6f}")
    print(f"  P99:    {threshold_high:.6f}")
    print(f"  Max:    {np.max(mse_per_sample):.6f}")

    return {
        'threshold_low': float(threshold_low),
        'threshold_high': float(threshold_high),
        'mean_error': float(np.mean(mse_per_sample)),
        'std_error': float(np.std(mse_per_sample)),
    }


def convert_to_tflite(model: keras.Model, output_path: str,
                       quantize: bool = True) -> str:
    """Convert Keras model to TFLite with optional float16 quantization."""

    converter = tf.lite.TFLiteConverter.from_keras_model(model)

    if quantize:
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.target_spec.supported_types = [tf.float16]

    tflite_model = converter.convert()

    with open(output_path, 'wb') as f:
        f.write(tflite_model)

    size_kb = len(tflite_model) / 1024
    print(f"\nTFLite model saved: {output_path} ({size_kb:.1f} KB)")

    return output_path


def save_scaler(scaler: StandardScaler, feature_names: list, output_path: str):
    """Save scaler parameters as JSON for Flutter app."""
    params = {
        'mean': scaler.mean_.tolist(),
        'scale': scaler.scale_.tolist(),
        'feature_names': feature_names,
    }

    with open(output_path, 'w') as f:
        json.dump(params, f, indent=2)

    print(f"Scaler parameters saved: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description='Train vibration anomaly detection autoencoder for AncientVision v3.0'
    )
    parser.add_argument('--input', '-i', type=str, default=None,
                       help='Input CSV or JSON file with vibration features')
    parser.add_argument('--output-dir', '-o', type=str, default='.',
                       help='Output directory for model files')
    parser.add_argument('--synthetic', action='store_true', default=False,
                       help='Use synthetic training data (for initial model)')
    parser.add_argument('--epochs', type=int, default=200,
                       help='Maximum training epochs')
    parser.add_argument('--no-quantize', action='store_true',
                       help='Skip model quantization')

    args = parser.parse_args()

    # If no input specified and not synthetic, default to synthetic
    if args.input is None and not args.synthetic:
        print("No input data specified. Using synthetic normal data for initial model.")
        print("To use real data: python train_vibration_autoencoder.py -i sensor_data.csv")
        print()
        args.synthetic = True

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Load or generate data
    if args.synthetic:
        df = generate_synthetic_normal_data(2000)
    elif args.input.endswith('.json') or args.input.endswith('.jsonl'):
        df = load_json_data(args.input)
    else:
        df = load_csv_data(args.input)

    # Use available features
    feature_cols = [f for f in FEATURE_NAMES if f in df.columns]
    X = df[feature_cols].values.astype(np.float32)

    print(f"\nUsing {len(feature_cols)} features: {feature_cols}")
    print(f"Data shape: {X.shape}")

    # Normalize features
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    # Train/validation split
    X_train, X_val = train_test_split(X_scaled, test_size=0.2, random_state=42)
    print(f"Training: {X_train.shape[0]} samples, Validation: {X_val.shape[0]} samples")

    # Build and train model
    print("\n--- Building Autoencoder v3.0 ---")
    model = build_autoencoder(input_dim=len(feature_cols))
    model.summary()

    print("\n--- Training ---")
    history = train_model(model, X_train, X_val, epochs=args.epochs)

    final_loss = history.history['val_loss'][-1]
    print(f"\nFinal validation loss: {final_loss:.6f}")

    # Compute anomaly thresholds
    thresholds = compute_thresholds(model, X_scaled)

    # Save model and config
    tflite_path = str(output_dir / 'vibration_anomaly.tflite')
    convert_to_tflite(model, tflite_path, quantize=not args.no_quantize)

    scaler_path = str(output_dir / 'vibration_scaler.json')
    save_scaler(scaler, feature_cols, scaler_path)

    config_path = str(output_dir / 'vibration_model_config.json')
    config = {
        'model_version': '3.0',
        'input_features': feature_cols,
        'input_dim': len(feature_cols),
        'thresholds': thresholds,
        'training_samples': len(X),
        'synthetic_data': args.synthetic,
        'description': 'Autoencoder v3.0 for archaeological site vibration anomaly detection',
        'standard': 'DIN 4150-3',
    }
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
    print(f"Model config saved: {config_path}")

    # Copy model to Flutter assets if the directory exists
    flutter_ml_dir = Path(__file__).parent.parent / 'assets' / 'ml'
    if flutter_ml_dir.exists():
        import shutil
        for fname in ['vibration_anomaly.tflite', 'vibration_scaler.json', 'vibration_model_config.json']:
            src = output_dir / fname
            dst = flutter_ml_dir / fname
            shutil.copy2(str(src), str(dst))
            print(f"Copied to Flutter assets: {dst}")

    print("\n--- Training Complete ---")
    print(f"Model:  {tflite_path}")
    print(f"Scaler: {scaler_path}")
    print(f"Config: {config_path}")
    print(f"\nDeploy to Flutter: copy all 3 files to assets/ml/")
    print(f"Then run: flutter build apk --release")


if __name__ == '__main__':
    main()
