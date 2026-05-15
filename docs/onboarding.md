# Wi-Fi, Bluetooth, and Onboarding

The Bobcat 300 hardware includes Wi-Fi and Bluetooth capability, but this image
does not yet expose Helium-app-compatible Bluetooth onboarding.

## Current Supported Path

The current image supports Ethernet DHCP, local web UI setup, `gateway-rs`, and
the SX1302 packet forwarder. For data-only onboarding and location assertion,
use the official Helium CLI wallet flow from a separate trusted computer rather
than installing wallet keys on the hotspot.

High-level flow:

1. Get the hotspot key from the Bobcat with `helium_gateway key info`.
2. Generate an add transaction with `helium_gateway add --owner <OWNER> --payer <PAYER>`.
3. Sign and submit with `helium-wallet hotspots add iot <TXN> --commit`.
4. Assert location with `helium-wallet hotspots update iot <HOTSPOT_KEY> --lat <LAT> --lon <LON> --gain <DBI> --elevation <METERS> --commit`.

Helium's data-only docs note that add and location assert transactions each
require Data Credits, plus SOL for transaction fees.

## Practical Wi-Fi Support

Adding Wi-Fi through this project's web UI is a reasonable near-term feature.
The likely implementation is:

- include NetworkManager, `wpa_supplicant`, and the Bobcat Wi-Fi firmware
- add a web UI page to scan SSIDs
- write a Wi-Fi connection profile from the submitted SSID/password
- restart networking and show the current wireless IP

That is independent of Helium app onboarding and should be much simpler to test.

## Helium App Bluetooth Support

Helium-app-compatible Bluetooth onboarding is a larger feature. It requires a
BLE GATT service that behaves like a maker hotspot, including characteristics
for Wi-Fi services, Wi-Fi credentials, diagnostics, onboarding key, public key,
and transaction handoff.

Even with BLE implemented, app-based add/location flows can depend on current
Helium wallet/app behavior and maker/onboarding-server expectations. For this
project, treat BLE app support as a compatibility project after the base image,
web UI, and CLI onboarding path are stable.

Useful official references:

- Helium Data-Only Hotspot Onboarding:
  https://docs.helium.com/iot/data-only-hotspots-onboarding/
- Helium Data-Only Hotspots:
  https://docs.helium.com/iot/data-only-hotspots/
- Helium Hotspot BLE Services:
  https://docs.helium.com/hotspot-makers/become-a-maker/hotspot-ble-services
