# Introduction

These Open Computers (OC) scripts will automatically tier-up, stat-up, and spread (duplicate) IC2 crops for you. OC is a very powerful yet complicated mod using custom scripts, but fear not. I have made everything here as straightforward as possible to help you get your crop bot running in no time without any prior knowledge of OC.

# Bare Minimum Components
- OC Electronics Assembler
- OC Charger
- OC Sensor
- Tier 3 Computer Case x2
- Linked card x2
- Tier 2 Memory x3
- Tier 2 Accelerated Processing Unit x2
- Tier 1 Redstone Card
- Tier 1 Hard Disk Drive x2
- Tier 1 Screen
- Tier 2 Screen
- Keyboard x2
- Disk Drive (Block) 
- Internet Card x2
- Inventory Controller Upgrade
- Inventory Upgrade
- EEPROM (Lua BIOS) x2
- OpenOS Floppy Disk
- Transvector Binder (Thaumcraft, Thaumic Tinkerer)
- Transvector Dislocator (Thaumcraft,Thaumic Tinkerer)
- Weeding Trowel (IC2)

# Building the Farms

Find a location with good environmental stats. It is recommended to set everything up in a Jungle or Swamp biome at Y=130 as that will give you the highest humidity and air quality stats. If not, crops run the risk of randomly dying and leaving the farms susceptible to weeds. Do not place any solid blocks above the farm as that will reduce the air quality. The whole farm can easily fit into a single chunk for easy chunk loading.

![Farm Top](media/prepare_farm.png?)

First note the orientation of the robot sitting atop the OC charger. It must face towards the right-most column of the working farm. Adjacent to the OC charger is the crop stick chest which can be a few things: any sort of large chest, a storage drawer (orientation does not matter). If the crop stick chest is ever empty, bad things will happen. Next to that is a trash can for any random drops that the robot picks up such as weeds, seed bags, and crop sticks but this can be swapped with another chest to recycle some of the materials. The transvector dislocator sits facing the top of the blank farmland (where a crop would go). The blank farmland itself acts as a buffer between the working and storage farms. There is no need to use a crop-matron, as it hydrates or fertilizes only half of the working farm. If you want to install a crop matron, the main thing is that its height should not be above ground level.

The location of the water is completely flexible: they do not have to be in the same locations as in the photo (underneath all five grates) and you can have as many as you would like on both the working farm and storage farm. BUT if you want to use the autoTier scheme {BETA}, stick to the location in the photo. However, **there MUST be a block on top of each water** and no two can be next to each other. The block can be literally anything, even a lily pad will work, so long as there is something.

The starting crops must be placed manually in the checkerboard pattern seen in the photo. This layout goes for all three programs. If you have only one seed, place it in the target group cage, and any mode will use it to start spreading.

![Farm Bottom](media/Farm_Bottom.png?)

Underneath the farm, you can see that there are three additional dirt blocks below each farmland, each of which add to the nutrient stat of the crop above it. For crops requiring a block underneath, that should be placed at the bottom. In this case, I have diareed planted on top which means I have one farmland --> two dirt --> one diamond block underneath each one. I do not have diamond blocks underneath the working farm because the diareed does not need to be fully grown in order to spread. 





# Building the Computer
![Robot Components](media/Computer_Components.png?)
1) Place the computer case.
2) Place screen and keyboard like on image
3) Shift-click all of the components into the computer case
4) Power on
5) Follow the commands on screen 'install' --> 'Y' --> 'Y' (Note: The OpenOS floppy disk is no longer needed in the computer afterwards)
6) Install the required scripts by copying this line of code into the computer (middle-click to paste)
   
       wget https://raw.githubusercontent.com/ForgTav/E2EE-CropAutomation/main/sysSetup.lua && sysSetup
7) Connect the sensor to the computer or monitor using a cable from OpenComputers.

![Robot Components](media/building_computer.png?)
![Robot Components](media/building_computer_2.png?)


# Building the Robot
![Robot Components](media/Robot_Components.png?)
1) Insert the computer case into the OC Electronics Assembler which can be powered.
2) Insert all of the components into the computer case like on image
3) Click assemble and wait until it completes (~3 min).
4) Rename the robot in an anvil.
5) Place the robot on the OC Charger which can also be powered. The OC Charger must be activated using some form of redstone such as a lever.
6) Insert the OpenOS floppy disk into the disk slot of the robot and press the power button
7) Follow the commands on screen 'install' --> 'Y' --> 'Y' (Note: The OpenOS floppy disk is no longer needed in the robot afterwards)
8) Install the required scripts by copying this line of code into the robot (middle-click to paste)

       wget https://raw.githubusercontent.com/ForgTav/E2EE-CropAutomation/main/robotSetup.lua && robotSetup
   
9) Place the Weeding Trowel and Transvector Binder into the last and second to last slot of the robot, respectively. Crop sticks will go in the third, but it is not required to put them in yourself. An axe or mattock can also be placed into the tool slot of the robot to speed up destroying crops (optional). See image below.
10) Print `` start `` on the robot command line

![Robot Inventory](media/Robot_Inventory.png?)


# Running the system
Launching the system on the computer using the command main.

    main

# autoStat
The autoStat program will automatically improve the traits of your target crop until the sum of Gr + Ga - Re reaches at least 52 for the target crop on the working farm. Any plants with traits above these will be interpreted as weeds and removed. If a plant is different from the target crop, it will be destroyed.

# autoTier
The program **autoTier** will automatically tier-up your crops until the max breeding round is reached (configurable) or the storage farm is full.

1) Schema Mode[BETA]: Used for breeding plants according to a specified scheme. You can start with a reed crop. The final layout will look as shown in the image.
![Schema_Beta](media/schema_beta.png?)

2) Target Crop Mode: Focuses on a specific target plant. The target plant is determined during initialization through scanning in target crop slot. Moves found target plants to parent slots

Modes are switched through the interface in the "AutoTier" menu, where you can choose between: "schema {BETA}" and a specific plant (targetCrop)

Initially, at startup, (targetCrop) is default.


# autoSpread
The program **autoSpread** will automatically spread (duplicate) your target crop until the storage farm is full.


# Interface
After you enter "main", the mode selection menu will open. Choose a mode by clicking the left mouse button.
![Schema_Beta](media/ui_start.png?)



The main process tracking menu then opens. Tabs are located on the left side of the menu, while information is displayed on the right. At the bottom, there are "start" and "exit" buttons.

The "Start" button launches the system, and "Exit" terminates it. 

In the "Exit" tab, there are two exit modes available: "Cleanup" and "Force exit." The "Cleanup" mode removes all unnecessary plants from the farm before ending the program.

![Schema_Beta](media/ui_after_init.png?)

Slot 00, where the charger is located, is directly below slot 01 on the working farm or two blocks to the left of slot 03 in the storage. This allows the system to determine the location of each plant.


When the system prepares a new order for the robot, the phrase "Loading..." appears in the top right corner. During this time, the user interface becomes unresponsive. This is due to single-threading.
![Schema_Beta](media/ui_loading.png?)

XX slots on the working farm indicate those that are not used in the current mode. Be careful when starting the system and ensure that there are no plants in the unused slots.

# Troubleshooting

1) The Transvector Dislocator is randomly moved to somewhere on the working farm

_Solution: Cover your water sources. Otherwise the order of the transvector binder will get messed up and teleport the dislocator instead of a crop._

2) The Robot is randomly moved to somewhere on the working farm

_Solution: Check the orientation of the transvector dislocator. This can only happen if the dislocator is facing up instead of forward._

3) The Robot is destroying all of the crops that were manually placed

_Solution: Either the resistance or growth stats of the parent crops are too high. By default, anything above 2 resistance or 21 growth is treated like a weed and will be removed._

4) Crops are randomly dying OR the farms are being overrun with weeds OR there are single crop sticks where there should be double

_Solution: Possibly change location. Crops have minimum environmental stat requirements (nutrients, humidity, air quality) and going below this threshold will kill the crop and leave an empty crop stick behind that is susceptible to growing weeds and overtaking the farms._

5) There is a PKIX path building error when downloading the files from GitHub

_Solution: This is from having outdated java certificates. Try updating your java (21 is recommended), but be prepared to manually install the files by copy-pasting the code from GitHub. The "Other Helpful Commands" section below can help with that._

6)  The robot is inactive after startup

_Solution: Ensure the charger is connected correctly. The Mekanism cube cannot directly transfer energy to the charger. Or mechanism cable cant power OS charger._

# Known Issues
1) If you plant a crop in the last slot, the system will consider the storage farm to be full.

## Other Helpful Commands

To list all of the files installed on the robot, enter

    ls

To edit (or create) a new file, enter

    edit <filename>.lua

To remove any one file installed on the robot, enter

    rm <filename>

To uninstall the system on computer or robot, enter

    uninstall
    

## Thanks
Huge thanks to Margatroid for the help with debugging and the ideas contributed to this project.

This project is based on [GTNH-CropAutomation](https://github.com/DylanTaylor1/GTNH-CropAutomation) by [DylanTaylor1](https://github.com/DylanTaylor1).

