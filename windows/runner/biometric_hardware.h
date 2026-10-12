#ifndef RUNNER_BIOMETRIC_HARDWARE_H_
#define RUNNER_BIOMETRIC_HARDWARE_H_

#include <windows.h>
#include <winbio.h>

// Query the biometric framework rather than Hello's generic availability,
// which can be true on a machine with only a PIN. Unsupported factors and
// disabled/unavailable services fail closed without presenting an auth prompt.
inline bool HasBiometricHardware() {
  const WINBIO_BIOMETRIC_TYPE factors[] = {
      WINBIO_TYPE_FINGERPRINT, WINBIO_TYPE_FACIAL_FEATURES, WINBIO_TYPE_IRIS};
  bool found = false;
  for (const auto factor : factors) {
    PWINBIO_UNIT_SCHEMA units = nullptr;
    SIZE_T count = 0;
    const HRESULT status = WinBioEnumBiometricUnits(factor, &units, &count);
    if (SUCCEEDED(status) && count > 0 && units != nullptr) found = true;
    if (units != nullptr) WinBioFree(units);
  }
  return found;
}

#endif  // RUNNER_BIOMETRIC_HARDWARE_H_
