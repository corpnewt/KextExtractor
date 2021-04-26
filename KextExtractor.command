#!/usr/bin/env python
# 0.0.0
from Scripts import *
import os, tempfile, datetime, shutil, time, plistlib, json, sys, glob

class KextExtractor:
    def __init__(self, **kwargs):
        self.r  = run.Run()
        self.d  = disk.Disk()
        self.u  = utils.Utils("KextExtractor")
        self.clover = None
        self.efi    = None
        # Get the tools we need
        self.script_folder = "Scripts"
        self.settings_file = os.path.join("Scripts", "settings.json")
        cwd = os.getcwd()
        os.chdir(os.path.dirname(os.path.realpath(__file__)))
        if self.settings_file and os.path.exists(self.settings_file):
            self.settings = json.load(open(self.settings_file))
        else:
            self.settings = {
                # Default settings here
                "archive" : False,
                "full" : False,
                "efi" : None,
                "kexts" : None
            }
        # Flush the settings to start
        self.flush_settings()
        os.chdir(cwd)

    def flush_settings(self):
        if self.settings_file:
            cwd = os.getcwd()
            os.chdir(os.path.dirname(os.path.realpath(__file__)))
            json.dump(self.settings, open(self.settings_file, "w"))
            os.chdir(cwd)

    def get_binary(self, name):
        # Check the system, and local Scripts dir for the passed binary
        found = self.r.run({"args":["which", name]})[0].split("\n")[0].split("\r")[0]
        if len(found):
            # Found it on the system
            return found
        if os.path.exists(os.path.join(os.path.dirname(os.path.realpath(__file__)), name)):
            # Found it locally
            return os.path.join(os.path.dirname(os.path.realpath(__file__)), name)
        # Check the scripts folder
        if os.path.exists(os.path.join(os.path.dirname(os.path.realpath(__file__)), self.script_folder, name)):
            # Found it locally -> Scripts
            return os.path.join(os.path.dirname(os.path.realpath(__file__)), self.script_folder, name)
        # Not found
        return None

    def get_efi(self):
        self.d.update()
        clover = bdmesg.get_bootloader_uuid()
        i = 0
        disk_string = ""
        if not self.settings.get("full", False):
            clover_disk = self.d.get_parent(clover)
            mounts = self.d.get_mounted_volume_dicts()
            for d in mounts:
                i += 1
                disk_string += "{}. {} ({})".format(i, d["name"], d["identifier"])
                if self.d.get_parent(d["identifier"]) == clover_disk:
                # if d["disk_uuid"] == clover:
                    disk_string += " *"
                disk_string += "\n"
        else:
            mounts = self.d.get_disks_and_partitions_dict()
            disks = mounts.keys()
            for d in disks:
                i += 1
                disk_string+= "{}. {}:\n".format(i, d)
                parts = mounts[d]["partitions"]
                part_list = []
                for p in parts:
                    p_text = "        - {} ({})".format(p["name"], p["identifier"])
                    if p["disk_uuid"] == clover:
                        # Got Clover
                        p_text += " *"
                    part_list.append(p_text)
                if len(part_list):
                    disk_string += "\n".join(part_list) + "\n"
        height = len(disk_string.split("\n"))+13
        if height < 24:
            height = 24
        self.u.resize(80, height)
        self.u.head()
        print(" ")
        print(disk_string)
        if not self.settings.get("full", False):
            print("S. Switch to Full Output")
        else:
            print("S. Switch to Slim Output")
        print("B. Select the Boot Drive's EFI")
        if clover:
            print("C. Select the Booted Clover/OC's EFI")
        print("")
        print("M. Main")
        print("Q. Quit")
        print(" ")
        print("(* denotes the booted Clover/OC)")

        menu = self.u.grab("Pick the drive containing your EFI:  ")
        if not len(menu):
            return self.get_efi()
        if menu.lower() == "q":
            self.u.custom_quit()
        elif menu.lower() == "m":
            return None
        elif menu.lower() == "s":
            full = self.settings.get("full", False)
            self.settings["full"] = not full
            self.flush_settings()
            return self.get_efi()
        elif menu.lower() == "b":
            return self.d.get_efi("/")
        elif menu.lower() == "c" and clover:
            return self.d.get_efi(clover)
        try:
            disk_iden = int(menu)
            if not (disk_iden > 0 and disk_iden <= len(mounts)):
                # out of range!
                self.u.grab("Invalid disk!", timeout=3)
                return self.get_efi()
            if type(mounts) is list:
                # We have the small list
                disk = mounts[disk_iden-1]["identifier"]
            else:
                # We have the dict
                disk = mounts.keys()[disk_iden-1]
        except:
            disk = menu
        iden = self.d.get_identifier(disk)
        name = self.d.get_volume_name(disk)
        if not iden:
            self.u.grab("Invalid disk!", timeout=3)
            return self.get_efi()
        # Valid disk!
        return self.d.get_efi(iden)

    def qprint(self, message, quiet):
        if not quiet:
            print(message)

    def mount_and_copy(self, disk, package, quiet = False):
        # Mounts the passed disk and extracts the package target to the destination
        self.d.update()
        if not quiet:
            self.u.head("Extracting {} to {}...".format(os.path.basename(package), disk))
            print("")
        if self.d.is_mounted(disk):
            mounted = True
        else:
            mounted = False
        # Mount the EFI if needed
        if not mounted:
            self.qprint("Mounting {}...".format(disk), quiet)
            out = self.d.mount_partition(disk)
            if not out[2] == 0:
                print(out[1])
                return False
            self.qprint(out[0].strip("\n"), quiet)
            self.qprint(" ", quiet)
        # Make sure we have the right folders in there
        mp = self.d.get_mount_point(disk)
        kexts = []
        temp = None
        # We need to parse some lists
        # First we need to get a list of zips and extract them to the temp folder
        self.qprint("Gathering files...",quiet)
        zips = [x for x in os.listdir(package) if not x.startswith(".") and x.lower().endswith(".zip")]
        if len(zips):
            self.qprint("\n - Extracting zip files...",quiet)
            # Create a temp folder
            temp = tempfile.mkdtemp()
            for f in zips:
                ztemp = tempfile.mkdtemp(dir=temp)
                args = [
                    "unzip",
                    os.path.join(package, f),
                    "-d",
                    ztemp
                ]
                self.qprint(" --> Extracting {}...".format(f), quiet)
                self.r.run({"args":args, "stream":False})
            # Let's iterate through the temp dir
            self.qprint("\n - Walking temp folder...",quiet)
            for path, subdirs, files in os.walk(temp):
                for name in subdirs:
                    if name.lower().endswith(".kext"):
                        # Save it
                        self.qprint(" --> {}".format(name),quiet)
                        kexts.append(os.path.join(path, name))
        self.qprint("\n - Walking {}".format(package),quiet)
        for path, subdirs, files in os.walk(package):
            for name in subdirs:
                if name.lower().endswith(".kext"):
                    # Save it
                    self.qprint(" --> {}".format(name),quiet)
                    kexts.append(os.path.join(path, name))
        # Got our lists
        if not len(kexts):
            self.qprint("\nNothing to install!", quiet)
            if temp: shutil.rmtree(temp, ignore_errors=True)
            return
        self.qprint("", quiet)
        for k_f in (os.path.join(mp, "EFI", "CLOVER", "kexts"), os.path.join(mp,"EFI","OC","Kexts")):
            print("Checking for {}...".format(k_f))
            if not os.path.exists(k_f):
                print(" - Not found!  Skipping...\n".format(k_f))
                continue
            print(" - Located!  Iterating...")
            # Install them - let's iterate through all the kexts we have,
            # then copy over what we need
            f_d = [os.path.join(k_f,x) for x in os.listdir(k_f) if os.path.isdir(os.path.join(k_f, x)) and (x.lower() == "other" or x.startswith("10."))]
            f_d.append(k_f) # Add the original top-level folder
            for k in kexts:
                for f in f_d:
                    self.check_kext(k,f)
            print("")
        if temp: shutil.rmtree(temp, ignore_errors=True)
        # Unmount if need be
        if not mounted:
            self.d.unmount_partition(disk)

    def check_kext(self,kext,kext_folder):
        if os.path.basename(kext.lower()) in [x.lower() for x in os.listdir(kext_folder)]:
            print(" --> Found {} in {} - removing and replacing...".format(os.path.basename(kext), os.path.basename(kext_folder)))
            # Remove, and replace here
            # Check if we're archiving - and zip if need be
            if self.settings.get("archive", False):
                print("   Archiving...")
                zip_name = "{}-Backup-{:%Y-%m-%d %H.%M.%S}.zip".format(os.path.basename(kext), datetime.datetime.now())
                args = [
                    "zip",
                    "-r",
                    os.path.join(kext_folder, zip_name),
                    os.path.join(kext_folder, os.path.basename(kext))
                ]
                out = self.r.run({"args":args, "stream":False})
                if not out[2] == 0:
                    print("   Couldn't backup {} - skipping!".format(os.path.basename(kext)))
                    return
            shutil.rmtree(os.path.join(kext_folder, os.path.basename(kext)), ignore_errors=True)
            shutil.copytree(kext, os.path.join(kext_folder, os.path.basename(kext)))

    def get_folder(self):
        self.u.head()
        print(" ")
        print("Q. Quit")
        print("M. Main Menu")
        print(" ")
        kexts = self.u.grab("Please drag and drop a folder containing kexts to copy:  ")
        if kexts.lower() == "q":
            self.u.custom_quit()
        elif kexts.lower() == "m":
            return None
        kexts = self.u.check_path(kexts)
        if not kexts:
            self.u.grab("Folder doesn't exist!", timeout=5)
            self.get_folder()
        return kexts

    def default_folder(self):
        self.u.head()
        print(" ")
        print("Q. Quit")
        print("M. Main Menu")
        print(" ")
        kexts = self.u.grab("Please drag and drop a default folder containing kexts:  ")
        if kexts.lower() == "q":
            self.u.custom_quit()
        elif kexts.lower() == "m":
            return self.settings["kexts"]
        kexts = self.u.check_path(kexts)
        if not kexts:
            self.u.grab("Folder doesn't exist!", timeout=5)
            return self.default_folder()
        return kexts

    def default_disk(self):
        self.d.update()
        clover = bdmesg.get_bootloader_uuid()
        self.u.resize(80, 24)
        self.u.head("Select Default Disk")
        print(" ")
        print("1. None")
        print("2. Boot Disk")
        if clover:
            print("3. Booted Clover/OC")
        print(" ")
        print("M. Main Menu")
        print("Q. Quit")
        print(" ")
        menu = self.u.grab("Please pick a default disk:  ")
        if not len(menu):
            return self.default_disk()
        menu = menu.lower()
        if menu in ["1","2"]:
            return [None, "boot"][int(menu)-1]
        elif menu == "3" and clover:
            return "clover"
        elif menu == "m":
            return self.settings["efi"]
        elif menu == "q":
            self.u.custom_quit()
        return self.default_disk()

    def main(self):
        efi = self.settings.get("efi", None)
        if efi == "clover":
            efi = self.d.get_identifier(bdmesg.get_bootloader_uuid())
        elif efi == "boot":
            efi = "/"
        kexts = self.settings.get("kexts", None)
        while True:
            self.u.head("Kext Extractor")
            print(" ")
            print("Target EFI:    "+str(efi))
            print("Target Folder: "+str(kexts))
            print("Archive:       "+str(self.settings.get("archive", False)))
            print(" ")
            print("1. Select EFI")
            print("2. Select Kext Folder")
            print(" ")
            print("3. Toggle Archive")
            print("4. Pick Default EFI")
            print("5. Pick Default Kext Folder")
            print(" ")
            print("6. Extract")
            print(" ")
            print("Q. Quit")
            print(" ")
            menu = self.u.grab("Please select an option:  ")
            if not len(menu):
                continue
            menu = menu.lower()
            if menu == "q":
                self.u.custom_quit()
            elif menu == "1":
                efi = self.get_efi()
            elif menu == "2":
                k = self.get_folder()
                if not k:
                    continue
                kexts = k
            elif menu == "3":
                arch = self.settings.get("archive", False)
                self.settings["archive"] = not arch
                self.flush_settings()
            elif menu == "4":
                efi = self.default_disk()
                self.settings["efi"] = efi
                if efi == "clover":
                    efi = self.d.get_identifier(bdmesg.get_bootloader_uuid())
                elif efi == "boot":
                    efi = self.d.get_identifier("/")
                self.flush_settings()
            elif menu == "5":
                kexts = self.default_folder()
                self.settings["kexts"] = kexts
                self.flush_settings()
            elif menu == "6":
                if not efi:
                    efi = self.get_efi()
                if not efi:
                    continue
                if not kexts:
                    k = self.get_folder()
                    if not k:
                        continue
                    kexts = k
                # Got folder and EFI - let's do something...
                self.mount_and_copy(efi, kexts, False)
                self.u.grab("Press [enter] to return...")

    def quiet_copy(self, args):
        # Iterate through the args
        arg_pairs = zip(*[iter(args)]*2)
        for pair in arg_pairs:
            efi = self.d.get_efi(pair[1])
            if efi:
                try:
                    self.mount_and_copy(self.d.get_efi(pair[1]), pair[0], True)
                except Exception as e:
                    print(str(e))

if __name__ == '__main__':
    c = KextExtractor()
    # Check for args
    if len(sys.argv) > 1:
        # We got command line args!
        # KextExtractor.command /path/to/kextfolder disk#s# /path/to/other/kextfolder disk#s#
        c.quiet_copy(sys.argv[1:])
    else:
        c.main()
