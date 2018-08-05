# KextExtractor
Small py script to extract kext files from a target folder and copy them to a target drive's EFI partition.

***

## To install:

Do the following one line at a time in Terminal:

    git clone https://github.com/corpnewt/KextExtractor
    cd KextExtractor
    chmod +x KextExtractor.command
    
Then run with either `./KextExtractor.command` or by double-clicking *KextExtractor.command*

***

## Usage:

Starting the script with no arguments will open it in interactive mode.

If you want it to auto extract & copy, you can pass pairs of arguments to it like so (assumes you have a Kexts folder on the Desktop, and plan to extract it to the boot drive's EFI):

    ./KextExtractor.command ~/Desktop/Kexts /
    
You can also pass multiple sets of argument pairs to extract multiple Kexts folders to EFIs.  With our above example, if we also wanted to extract that same folder to `disk5`'s EFI, we could do:

    ./KextExtractor.command ~/Desktop/Kexts / ~/Desktop/Kexts disk5

***

## Thanks To:

* Slice, apianti, vit9696, Download Fritz, Zenith432, STLVNUB, JrCs,cecekpawon, Needy, cvad, Rehabman, philip_petev, ErmaC and the rest of the Clover crew for Clover and bdmesg
