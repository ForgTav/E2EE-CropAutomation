# Introduction

These Open Computers (OC) scripts will automatically tier-up, stat-up, and spread (duplicate) IC2 crops for you. OC is a very powerful yet complicated mod using custom scripts, but fear not. I have made everything here as straightforward as possible to help you get your crop bot running in no time without any prior knowledge of OC.

# Bare Minimum Components

Obtaining these components will require access to EV circuits and epoxid (mid-late HV). It is possible to save some resources by not including the internet card, but that will require manually copying and pasting the code from GitHub which is NOT recommended for multiple reasons. Both inventory upgrades are necessary.

- OC Electronics Assembler
- OC Charger
- OC Sensor
- Tier 3 Computer Case x2
- Linked card x2
- Tier 2 Memory x2
- Tier 2 Accelerated Processing Unit x2
- Tier 1 Redstone Card
- Tier 1 Hard Disk Drive x2
- Tier 1 Screen x2
- Keyboard x2
- Disk Drive (Block) 
- Internet Card x2
- Inventory Controller Upgrade
- Inventory Upgrade
- EEPROM (Lua BIOS) x2
- OpenOS Floppy Disk
- Transvector Binder (Thaumcraft, Thaumic Tinkerer)
- Transvector Dislocator (Thaumcraft,Thaumic Tinkerer)

# Building the Farms

Find a location with good environmental stats. It is recommended to set everything up in a Jungle or Swamp biome at Y=130 as that will give you the highest humidity and air quality stats. If not, crops run the risk of randomly dying and leaving the farms susceptible to weeds. Do not place any solid blocks above the farm as that will reduce the air quality. The whole farm can easily fit into a single chunk for easy chunk loading.

![Farm Top](media/farm_first_step.png?)

![Farm Side](media/farm_first_step_side.png?)

First note the orientation of the robot sitting atop the OC charger. It must face towards the right-most column of the working farm. Adjacent to the OC charger is the crop stick chest which can be a few things: any sort of large chest, a JABBA barrel, or storage drawer (orientation does not matter). If the crop stick chest is ever empty, bad things will happen. Next to that is a trash can for any random drops that the robot picks up such as weeds, seed bags, and crop sticks but this can be swapped with another chest to recycle some of the materials. The transvector dislocator sits facing the top of the blank farmland (where a crop would go). The blank farmland itself acts as a buffer between the working and storage farms. Lastly, a crop-matron sits one y-level lower than the OC charger and hydrates most of the crops which boosts their stats and helps them grow faster.

The location of the water is completely flexible: they do not have to be in the same locations as in the photo (underneath all five grates) and you can have as many as you would like on both the working farm and storage farm. However, **there MUST be a block on top of each water** and no two can be next to each other. The block can be literally anything, even a lily pad will work, so long as there is something.

The starting crops must be placed manually in the checkerboard pattern seen in the photo. This layout goes for all three programs. If you cannot fill the entire checkerboard to start, the absolute minimum required is two (one as the target crop and the other next to it for crossbreeding). Even worse, if you have just a single seed of your target crop, it is possible to start with a different crop next to it for crossbreeding (ie. Stickreed). It is not necessary to place empty crop sticks to fill the rest of the checkerboard. The target crop is used by autoStat and autoSpread to identify the crop you want to stat-up or spread to the storage farm, respectively.

![Farm Bottom](media/Farm_Bottom.png?)

Underneath the farm, you can see that there are three additional dirt blocks below each farmland, each of which add to the nutrient stat of the crop above it. For crops requiring a block underneath, that should be placed at the bottom. In this case, I have diareed planted on top which means I have one farmland --> two dirt --> one diamond block underneath each one. I do not have diamond blocks underneath the working farm because the diareed does not need to be fully grown in order to spread. 



# Building the Robot
![Robot Components](media/Robot_Components.png?)
1) Insert the computer case into the OC Electronics Assembler which can be powered directly by any GT cable.
2) Insert all of the components into the computer case like on image
3) Click assemble and wait until it completes (~3 min).
4) Rename the robot in an anvil.
5) Place the robot on the OC Charger which can also be powered directly by any GT cable. The OC Charger must be activated using some form of redstone such as a lever.
6) Insert the OpenOS floppy disk into the disk slot of the robot and press the power button
7) Follow the commands on screen 'install' --> 'Y' --> 'Y' (Note: The OpenOS floppy disk is no longer needed in the robot afterwards)
8) Install the required scripts by copying this line of code into the robot (middle-click to paste)

        wget https://raw.githubusercontent.com/ForgTav/E2EE-CropAutomation/main/setup.lua && setup
   
10) Place the Weeding Trowel and Transvector Binder into the last and second to last slot of the robot, respectively. Crop sticks will go in the third, but it is not required to put them in yourself. An axe or mattock can also be placed into the tool slot of the robot to speed up destroying crops (optional). See image below.

![Robot Inventory](media/Robot_Inventory.png?)


# Building the Computer
![Robot Components](media/Com_Components.png?)
1) Place the computer case.
2) Place screen and keyboard on top the case
3) Shift-click all of the components into the computer case
4) Power on
5) Follow the commands on screen 'install' --> 'Y' --> 'Y' (Note: The OpenOS floppy disk is no longer needed in the robot afterwards)
6) Install the required scripts by copying this line of code into the robot (middle-click to paste)

        wget https://raw.githubusercontent.com/ForgTav/E2EE-CropAutomation/main/startServer.lua


# Running the Programs

The first program **autoTier** will automatically tier-up your crops until the max breeding round is reached (configurable), the storage farm is full, or ALL crops meet the specified tier threshold which defaults to 13. Note that unrecognized crops will be moved to the storage farm first before replacing any of the lower tier crops in the working farm. Statting-up crops during this program is also a configurable option, but that will slow down the process significantly. To run, simply enter:

    autoTier

The second program **autoStat** will automatically stat-up your target crop until the Gr + Ga - Re is at least 52 (configurable) for ALL crops on the working farm. Note that the maximum growth and resistance stats for parent crops are also configurable parameters which default to 21 and 2, respectively. Any crops with stats higher than these will be interpreted as weeds and removed. To run, simply enter:

    autoStat

The third program **autoSpread** will automatically spread (duplicate) your target crop until the storage farm is full. New crops will only be moved to the storage farm if their Gr + Ga - Re is at least 50 (configurable). Note that the maximum growth and resistance stats for child crops are also configurable parameters which default to 23 and 2, respectively. To run, simply enter:

    autoSpread

Lastly, these programs can be chained together which may be helpful if you have brand new crops (ie. 1/1/1 spruce saplings) and want them to immediately start spreading once they are fully statted-up. Note that keepMutations in the config should probably be set to false (default) otherwise the storage farm will be overwritten once the second program begins. To run autoSpread after autoStat, simply enter:

    autoStat && autoSpread

Turn off the OC Charger to pause the robot during any of these programs. The robot will not resume until it is fully charged. Press 'Q' while in the interface of the robot to terminate the program immediately, or press 'C' to terminate the program immediately AND cleanup. Lastly, changing anything in the config requires you to restart your robot.

# Troubleshooting

1) The Transvector Dislocator is randomly moved to somewhere on the working farm

_Solution: Cover your water sources. Otherwise the order of the transvector binder will get messed up and teleport the dislocator instead of a crop._

4) The Robot is randomly moved to somewhere on the working farm

_Solution: Check the orientation of the transvector dislocator. This can only happen if the dislocator is facing up instead of forward._

3) The Robot is destroying all of the crops that were manually placed

_Solution: Either the resistance or growth stats of the parent crops are too high. By default, anything above 2 resistance or 21 growth is treated like a weed and will be removed. These values, including the maximum stats of child crops, are all easily changed in the config._

4) Crops are randomly dying OR the farms are being overrun with weeds OR there are single crop sticks where there should be double

_Solution: Possibly change location. Crops have minimum environmental stat requirements (nutrients, humidity, air quality) and going below this threshold will kill the crop and leave an empty crop stick behind that is susceptible to growing weeds and overtaking the farms._

5) There is a PKIX path building error when downloading the files from GitHub

_Solution: This is from having outdated java certificates. Try updating your java (21 is recommended), but be prepared to manually install the files by copy-pasting the code from GitHub. The "Other Helpful Commands" section below can help with that._

6) There is an "execute_complex" error when downloading the files from GitHub or trying to run autoStat && autoSpread

_Solution: The execute complex refers to using the && operator. Double check that you installed at least Tier 2 memory. Anything less will prevent you from joining commands together._

## Recommended Crops

For starters, I recommend statting-up and spreading the following crops because their outputs are useful and not completely overshadowed by bees. Note that every crop has a higher chance of being discovered with specific parent combinations, but it is often easier to discover a crop from crossbreeding at the same tier. For example, diareed apparently has the highest chance of being discovered when the parents are oilberry and bobsyeruncleranks, BUT I recommend just running autoTier with all Tier 12 crops (or autoSpread with keepMutations on in the config). Crops that require a particular block underneath do not need to be fully grown in order to spread. For a full list of crops and their requirements, visit https://gtnh.miraheze.org/wiki/IC2_Crops_List.

- **Stickreed** for sticky resin and discovering/breeding with other crops
- **Spruce Bonsai** for all of your benzene and power needs
- **Black Stonelilly** for black granite dust (fluorine, potassium, magnesium, aluminium, silicon)
- **Nether Stonelilly** for netherrack dust (coal, sulfur, redstone, gold)
- **Yellow Stonelilly** for endstone dust (helium, tungstate, platinum metallic powder)
- **Sugarbeet** for sugar (oxygen)
- **Salty root** OR **Tearstalks** for salt (sodium and chlorine)
- **Enderbloom** for enderpearls and endereyes
- **Glowing Earth Coral** for sunnarium and glowstone (gold and redstone)
- **Rape** for seed oil
- **Goldfish Plant** for fish oil
- **Diareed** for diamonds
- **Bobsyeruncleranks** for emeralds
- **Transformium** for UU-Matter

## Other Helpful Commands

To list all of the files installed on the robot, enter

    ls

To edit (or create) a new file, enter

    edit <filename>.lua

To remove any one file installed on the robot, enter

    rm <filename>

To uninstall all of the files from this repo, enter

    uninstall

To view an entire error message regardless of how long it may be, enter

    <program> 2>/errors.log

    edit /errors.log

## Thanks
Huge thanks to huchenlei and xyqyear for their initial implementations and letting me take this project even further! Shoutout to Mozzg for also contributing to the repo!
