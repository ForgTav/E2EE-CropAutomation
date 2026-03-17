# 🌱 E2EE Crop Automation for OpenComputers + IC²

Automate your IC² crop breeding with ease using this fully integrated OpenComputers (OC) system. These scripts handle: **tiering up**, **stat maximization**, and **crop spreading** — all with minimal setup. No prior experience with OpenComputers is necessary — this guide walks you through everything step-by-step.

---

## ⚠️ Manual-only Crops

Some plants **cannot be automated** using this script due to their unique environmental requirements or mechanics.

### Example: Redwheat
- Requires **light level between 5 and 10**
- This condition cannot be reliably maintained or managed by the robot
- As a result, Redwheat must be grown and bred **manually**

If a plant has similar constraints, it is recommended to handle it outside the automated system.

## ⚙️ Required components for CropAutomation

| Component                    | Qty | Tier   | Mode                               |
| ---------------------------- | --- | ------ | ---------------------------------- |
| OC Charger                   | 1   | —      | OpenComputers                      |
| OC Sensor                    | 1   | —      | OpenComputers Sensors              |
| Power Converter              | 1   | —      | OpenComputers                      |
| Computer Case                | 2   | Tier 2 | OpenComputers                      |
| Screen                       | 1   | Tier 1 | OpenComputers                      |
| Screen                       | 1   | Tier 2 | OpenComputers                      |
| Keyboard                     | 2   | —      | OpenComputers                      |
| Accelerated Processing Unit  | 1   | Tier 2 | OpenComputers                      |
| Central Processing Unit      | 1   | Tier 2 | OpenComputers                      |
| Memory                       | 3   | Tier 2 | OpenComputers                      |
| Graphics Card                | 1   | Tier 2 | OpenComputers                      |
| Redstone Card                | 1   | Tier 1 | OpenComputers                      |
| Network Card                 | 2   | —      | OpenComputers                      |
| Hard Disk Drive              | 2   | Tier 1 | OpenComputers                      |
| Inventory Controller Upgrade | 1   | —      | OpenComputers                      |
| Inventory Upgrade            | 1   | —      | OpenComputers                      |
| EEPROM (Lua BIOS)            | 2   | —      | OpenComputers                      |
| Transvector Binder           | 1   | —      | Thaumic Tinkerer                   |
| Transvector Dislocator       | 1   | —      | Thaumic Tinkerer                   |
| Weeding Trowel               | 1   | —      | Industrial Craft 2                 |

## ⚙️ Assembly station components
| Component                    | Qty | Tier   | Mode                               |
| ---------------------------- | --- | ------ | ---------------------------------- |
| OC Electronics Assembler     | 1   | —      | OpenComputers                      |
| Computer Case                | 1   | Tier 2 | OpenComputers                      |
| Screen                       | 1   | Tier 1 | OpenComputers                      |
| Disk Drive (Block)           | 1   | —      | OpenComputers                      |
| Keyboard                     | 1   | —      | OpenComputers                      |
| Central Processing Unit      | 1   | Tier 1 | OpenComputers                      |
| Memory                       | 1   | Tier 1 | OpenComputers                      |
| Internet Card                | 1   | —      | OpenComputers                      |
| EEPROM (Lua BIOS)            | 1   | —      | OpenComputers                      |
| OpenOS Floppy Disk           | 1   | —      | OpenComputers                      |
---

## 🌾 Setting Up the Farm

Choose a location with high **humidity** and **air quality** (e.g., Jungle or Swamp at Y=130). Avoid placing solid blocks above the crops to maintain air quality. Ideally, keep everything inside a single chunk for easier chunk loading.
> 💡 **Note:** You can change the biome using tools like the Extra Utilities Terraformer to create more suitable conditions for crops.

![Farm Top](media/prepare_farm.png?)
Key setup details:

- The robot should face the **rightmost column** of the working farm.
- Next to the charger:
  - A **chest or drawer** for crop sticks
  - A **trash can** or optional recycling chest
- Place the **transvector dislocator** to face the **blank farmland** (used as a teleport buffer between working and storage farm).
   - ![Face side](media/transvector_dislocator_face.png?)

### Water Placement Guidelines

- Water can go anywhere — but for **autoTier mode**, use the suggested layout.
- **Each water source must be covered** (e.g., any solid block, lily pad or trapdoor).
- **Water blocks cannot be adjacent** to each other.

### Seeding the Farm

- Manually place the starter crops in a **checkerboard** pattern.
- One seed is enough — the system will multiply it by itself.
- The first farmland slot in front of the charger must have a crop planted. This acts as a reference point for the system to identify the target crop.
- If you don't have IC² seedlings, start with reeds.
![Ready farm](media/ready_farm.png?)

### Soil Structure

- Below each farmland tile: `farmland → dirt → dirt → nutrient block`
- Example: diareed crops require diamond blocks at the bottom — **only** in storage farm.
![Farm bottom](media/Farm_Bottom.png?)
---

## 🖥️ Setting Up the Assembly station
### ⚙️ Assembly station components

| Component                    | Qty | Tier   | Mode                               |
| ---------------------------- | --- | ------ | ---------------------------------- |
| Electronics Assembler        | 1   | —      | OpenComputers                      |
| Computer Case                | 1   | Tier 2 | OpenComputers                      |
| Screen                       | 1   | Tier 1 | OpenComputers                      |
| Disk Drive (Block)           | 1   | —      | OpenComputers                      |
| Keyboard                     | 1   | —      | OpenComputers                      |
| Central Processing Unit      | 1   | Tier 1 | OpenComputers                      |
| Memory                       | 1   | Tier 1 | OpenComputers                      |
| Internet Card                | 1   | —      | OpenComputers                      |
| EEPROM (Lua BIOS)            | 1   | —      | OpenComputers                      |
| OpenOS Floppy Disk           | 1   | —      | OpenComputers                      |

1. Place the computer Case, Screen, Keyboard, Disk Drive and Electronics Assembler.
2. Install all components.
   - ![Assembly Station Components](media/Assembly_station_components.png?)
3. Insert OpenOS floppy in Disk Drive

![Building assembly station](media/building_assembly_station.png?)

---

## 🤖 Building and Setting Up the Robot
### ⚙️ Robot components

| Component                    | Qty | Tier   | Mode                               |
| ---------------------------- | --- | ------ | ---------------------------------- |
| Computer Case                | 1   | Tier 2 | OpenComputers                      |
| Screen                       | 1   | Tier 1 | OpenComputers                      |
| Keyboard                     | 1   | —      | OpenComputers                      |
| Disk Drive (Block)           | 1   | —      | OpenComputers                      |
| Accelerated Processing Unit  | 1   | Tier 2 | OpenComputers                      |
| Memory                       | 1   | Tier 2 | OpenComputers                      |
| Hard Disk Drive              | 1   | Tier 1 | OpenComputers                      |
| Redstone Card                | 1   | Tier 1 | OpenComputers                      |
| Network Card                 | 1   | —      | OpenComputers                      |
| Inventory Controller Upgrade | 1   | —      | OpenComputers                      |
| Inventory Upgrade            | 1   | —      | OpenComputers                      |
| EEPROM (Lua BIOS)            | 1   | —      | OpenComputers                      |
| Transvector Binder           | 1   | —      | Thaumic Tinkerer                   |
| Transvector Dislocator       | 1   | —      | Thaumic Tinkerer                   |
| Weeding Trowel               | 1   | —      | Industrial Craft 2                 |

1. Insert Hard Disk Drive in Assembly station
   - ![Assembly station hard drive](media/Assembly_station_hard_drive.png?)
2. Power On the Assembly station, right click on screen and follow the prompt:
   ```text
   install → Y → Y
   ```
3. After reboot insert command
   ```text
   wget https://raw.githubusercontent.com/ForgTav/E2EE-CropAutomation/main/robotSetup.lua && robotSetup
   ```
4. Power Off the Assembly station, take the hard drive from the assembly station, and let's start assembling the robot in Electronics Assembler.
5. Insert computer case into the Electronics Assembler and required components.
   - ![Robot Components](media/Robot_Components.png?)
   > 💡 **Note:** Hard drive disk we were preparing at the assembly station.
6. Click assemble and wait (\~3 minutes).
7. Rename the robot using an anvil.
8. Place it on the OC Charger and activate the charger with redstone.
9. Equip:
   - Slot #16: Weeding Trowel
   - Slot #15: Transvector Binder
   - Slot #14: Crop sticks (optional; will auto-refill)
   - (Optional) Tool slot: Axe or Mattock
   - ![Robot Inventory](media/Robot_Inventory.png?)
10. Power On and in terminal, enter:
```text
start
```
11. The terminal will show an error if a part is missing.

---

## 🖥️ Setting Up the Computer
### ⚙️ Computer components

| Component                    | Qty | Tier   | Mode                               |
| ---------------------------- | --- | ------ | ---------------------------------- |
| OC Charger                   | 1   | —      | OpenComputers                      |
| OC Sensor                    | 1   | —      | OpenComputers                      |
| Power Converter              | 1   | —      | OpenComputers                      |
| Computer Case                | 1   | Tier 2 | OpenComputers                      |
| Screen                       | 1   | Tier 2 | OpenComputers                      |
| Keyboard                     | 1   | —      | OpenComputers                      |
| Central Processing Unit      | 1   | Tier 2 | OpenComputers                      |
| Memory                       | 2   | Tier 2 | OpenComputers                      |
| Graphics Card                | 1   | Tier 2 | OpenComputers                      |
| Network Card                 | 1   | —      | OpenComputers                      |
| Hard Disk Drive              | 1   | Tier 1 | OpenComputers                      |
| EEPROM (Lua BIOS)            | 1   | —      | OpenComputers                      |


1. Insert Hard Disk Drive in Assembly station
   - ![Assembly station hard drive](media/Assembly_station_hard_drive.png?)
2. Power On the Assembly station, right click on screen and follow the prompt:
   ```text
   install → Y → Y
   ```
3. After reboot insert command
   ```text
   wget https://raw.githubusercontent.com/ForgTav/E2EE-CropAutomation/main/sysSetup.lua && sysSetup
   ```
4. Power Off the Assembly station, take the hard drive from the assembly station, and let's start assembling the computer.
5. Place the Computer Case, Screen, and Keyboard.
   - ![Building computer](media/building_computer.png?)
6. Install all components.
   -  ![Computer Components](media/Computer_Components.png?)
7. Connect the Sensor, Charger, Computer case and Power Converter using a cable.
   -  ![Building computer 2](media/building_computer_2.png?)

![Building computer 3](media/building_computer_3.png?)

---

## 🚀 Running the System

Enter the following command in the computer's terminal:

```bash
main
```
The installation will be checked for correctness and the interface will open, otherwise it will open a step-by-step installation guide

### 🔄 Grid Handling
Each automation mode uses its own logical grid size for optimal performance:

- AutoTier → works on a 6×6 grid

- AutoStat → works on a 5×5 grid

- AutoSpread → works on a 5×5 grid

You do not need to manually change or reconfigure your actual farm layout —
the system automatically adapts to the proper working area depending on the selected mode.

### Mode: autoStat

Automatically boosts target crop traits until **(Growth + Gain - Resistance ≥ 52)**. You can edit these metrics in the UI settings tab. Crops exceeding this are treated as weeds and removed.

### Mode: autoTier

Crosses plants and automatically transfers newly bred crops to the storage area upon detection.
This mode includes two sub-modes:

- **Schema Mode:** Breeds according to a set pattern.
  - ![schema_crop](media/schema.png?)
- **Manual Mode:** The robot does not edit parent seedlings unless they are weeded.

### Mode: autoSpread

Duplicates the target crop and transfers to storage.

---

## 🧭 User Interface
![ui](media/ui.png?)

**The interface contains 5 tabs:**

1. **Farm**  
   This tab allows you to monitor the current state of your farm in real-time.  
   - Click on any farm slot to view detailed information about the plant occupying it.  
   - Displays additional data such as the number of available crop sticks and the fill status of the chest or trash containers.

2. **System**  
   This tab provides system controls where you can:  
   - Check the current status of the automation system.  
   - Start or shuts down the entire system.

3. **Actions**  
   Contains four key actions for managing your farm manually:  
   - **Transplant** — Select a plant from one slot and move it to another. This is especially useful for changing the `targetCrop` or when operating in AutoTier Manual Mode.  
   - **CleanUp** — Initiate a cleanup process to remove leftover crop sticks and unwanted plants (all plant children). It’s recommended to run this after stopping the system to prevent weed overgrowth.  
   - **Scan Farm** — Force a scan of the farm to update all plant data immediately.  
   - **Scan Storage** — Force a scan of the storage farm to update all plant data immediately.
   - **Scan Cropsticks chest** — Scan the crop sticks chest to update the internal count.

4. **Settings**  
   Here you can configure different operating modes and logging parameters to adapt the system behavior to your needs.

5. **Logs**  
   View detailed reports of the system’s actions and events. The log output depends on the selected logging settings and provides insights for troubleshooting and monitoring.

**Loading**

- When the system prepares a new order for the robot, the phrase "Loading.." appears in the bottom left corner. During this time, the user interface becomes unresponsive.

![Schema_Beta](media/ui_loading.png?)
---

## 💥 Force Termination

The system may automatically **terminate** itself under critical conditions to maintain stability:

#### Conditions:
- 🧯 Crop sticks fall below **one full stack**
- 📦 Storage farm is **completely full**

#### What happens:
- 🧹 A **forced cleanup** will run automatically to remove any unnecessary crops or leftover sticks.
- ❌ The system will **shut down** immediately after cleanup to prevent weed infestation or system failure.

> This mechanism protects your farm from becoming unstable due to missing resources or overflow.  
> If force termination occurs frequently, check your crop stick supply and make sure unused storage slots are available.  
> The logs will show the reason for the stop.

> 💡 **Note:** If the system doesn't allow you to start after a forced shutdown, open the **Actions** tab and run a scan of either the **storage** or the **cropsticks chest**.  
> This will reset the error flag and allow the system to resume normal operation.
---

## 🛠 Troubleshooting

**1. Transvector Dislocator teleports randomly**\
💡 Cover all water blocks to avoid targeting issues.  
💡 Make sure that the Transvector Dislocator is pointed at the blank farm.  

**2. Robot gets displaced**\
💡 Make sure dislocator faces **forward**, not **up**.

**3. Robot destroys placed crops**\
💡 Resistance >2 or Growth > 23 or Gain > 31 is treated as weed.

**4. Crops dying, weeds spreading**\
💡 Location may have poor humidity/air/soil — consider relocating.

**5. Computer can't communicate with the robot**  
💡 Disassemble the robot and remove the **Linked Cards** from both the robot and the computer. Combine them in a **crafting table** to synchronize the connection, then reinsert and try again.

**6. Robot doesn’t respond**\
💡 Mekanism energy cube or cables may not power the OC charger properly.  

**7. The robot and computer stopped unexpectedly and shut down**  
💡 This is likely caused by the chunk being unloaded. Make sure the farm is inside a **chunk-loaded area**.  
Install a **chunk loader** (e.g., from the IC² mod or another mod that provides chunk loading).

## 🧰 Helpful Commands

```bash
ls                  # List installed files
edit <file>.lua     # Edit or create script
rm <file>           # Delete file
uninstall           # Remove automation system
```

---

## 🙏 Thanks
**Huge thanks to _Margatroid_, _Mase_, _aretta35_, and _m9maoka_ for their help with testing and for providing valuable feedback that helped improve the system.** \
Project based on [GTNH-CropAutomation](https://github.com/DylanTaylor1/GTNH-CropAutomation) by [DylanTaylor1](https://github.com/DylanTaylor1).

