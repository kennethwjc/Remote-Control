#!/bin/bash

#~ Function to check and install a package if not installed
check_and_install_package() {
	#~ Declares a local variable and assigns it the value of the first argument passed to the function
    local package_name=$1
    #~ Checks if the package by checking debian package (dpkg -l)
    #~ If the package is not found, then execute the code inside the 'if' block
    if ! dpkg -l | grep -q "$package_name"; then
        echo "$package_name is not installed. Installing $package_name..."
        #~ Update the package list to ensure we have the latest information about available packages
        sudo apt-get update
        #~ Install package with '-y' flag to automatically answer 'yes' to prompts
        sudo apt-get install -y "$package_name"
        echo "$package_name installed successfully."
    else
		#~ If package is already installed, print this
        echo "$package_name is already installed."
        #~ Pause for 1 second before continuing
        sleep 1
    fi
}

#~ Call the function and install the following packages
check_and_install_package sshpass
check_and_install_package whois
check_and_install_package nmap

#~ 'find' command to locate the 'nipe.pl' file, starting from the root directory
#~ '-print -quit' prints the first match found and then quit the search. 
#~ '2>/dev/null' redirects any error messages to /dev/null to prevent them from being displayed.
echo "Searching for nipe.pl"
nipe_path=$(find / -type f -name "nipe.pl" -print -quit 2>/dev/null)
echo "Found nipe.pl at: $nipe_path"

#~ Define log file
log_file="/var/log/domain_scan.log"

#~ Function to log scan details
log_scan(){
	#~ Define a local variable and assign it the first and second argument passed to the function
    local domain=$1
    local scan_type=$2
    #~ Assigning 'log_time' to current date and time formatted as "Day Month Date Time Year"
    local log_time=$(date "+%a %b %d %H:%M:%S %Y")
    #~ 'tee -a' to append to the log file and redirect standard output of tee to /dev/null
    echo "$log_time - $scan_type data collected for: $domain" | sudo tee -a $log_file > /dev/null
}

#~ Check if nipe path is not empty
if [ -n "$nipe_path" ]; then
    #~ Extract the directory containing nipe.pl
    nipe_dir=$(dirname "$nipe_path")
    
    #~ Change to the directory containing nipe.pl
    #~ If fail, print message and exit the script
    cd "$nipe_dir" || { echo "Failed to change directory to $nipe_dir."; exit 1; }

    #~ Check the status of Nipe and extract IP address and country
    nipe_status=$(sudo perl nipe.pl status)
    nipe_running=$(echo "$nipe_status" | head -n2 | tail -n1 | awk '{print $3}')
    nipe_ip=$(echo "$nipe_status" | head -n3 | tail -n1 | awk '{print $3}')
    ip_country=$(whois "$nipe_ip" | grep -i country | awk '{print $2}')
    
    #~ Check if nipe is running
    if [ "$nipe_running" = "true" ]; then
        echo "Nipe is running and you are anonymous."
        sleep 1
        echo "Your spoofed IP address is $nipe_ip"
        sleep 1
        echo "The country you are connected to is $ip_country"
        sleep 1
        
        #~ Prompt user to enter credentials to ssh into a server
        read -p "Enter SSH username: " ssh_user
        read -s -p "Enter SSH password: " ssh_password
        echo
        read -p "Enter SSH server address: " ssh_server
        #~ Prompt user to enter the domain to scan and store the input in the variable target_domain
        read -p "Enter domain or URL to scan:" target_domain
        
		#~ Log the scan details
        log_scan "$target_domain" "whois and nmap"
        
        #~ cd out of the Nipe directory to the original directory
        cd ..
        
        #~ Define the file path for storing the outputs on the remote SSH server
        remote_whois_output="./whois_output.txt"
        remote_nmap_output="./nmap_output.txt"
        
        #~ Connect to SSH server and run commands, saving output to files
        echo "Connecting to SSH server..."
        #~ Use sshpass to pass the SSH password and connect to the SSH server and run the following commands
        sshpass -p "$ssh_password" ssh -o StrictHostKeyChecking=no "$ssh_user@$ssh_server" << EOF
            echo "Remote SSH server IP address:" > $remote_whois_output
            ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print \$2}' >> $remote_whois_output
            echo "Running whois on $target:" >> $remote_whois_output
            whois $target_domain >> $remote_whois_output
            echo "Running nmap scan on $target:" > $remote_nmap_output
            nmap $target_domain >> $remote_nmap_output
EOF

        #~ Check if the files were created on the remote server and verify their existence
        echo "Checking if output files were created on the remote server..."
        sshpass -p "$ssh_password" ssh -o StrictHostKeyChecking=no "$ssh_user@$ssh_server" "ls -l $remote_whois_output $remote_nmap_output"

        #~ Copy output files from the remote server to the local machine
        echo "Copying output files from remote server to local machine..."
        sshpass -p "$ssh_password" scp -o StrictHostKeyChecking=no "$ssh_user@$ssh_server:$remote_whois_output" .
        sshpass -p "$ssh_password" scp -o StrictHostKeyChecking=no "$ssh_user@$ssh_server:$remote_nmap_output" .
        
        #~ Verify the copied files
        echo "Verifying the copied files..."
        if [[ -f "whois_output.txt" ]]; then
            echo "whois output successfully copied to whois_output.txt"
        else
            echo "Failed to copy whois output"
        fi
        if [[ -f "nmap_output.txt" ]]; then
            echo "nmap output successfully copied to nmap_output.txt"
        else
            echo "Failed to copy nmap output"
        fi
        
    else
		#~ Restart nipe.pl is unable to run
        echo "Nipe is not running. Restarting Nipe..."
        sudo perl nipe.pl restart
        echo "Please run the script again to check the Nipe status."
    fi
else
	#~ Proceed to install nipe if not found
    echo "nipe.pl not found. Installing Nipe..."
    
    #~ Creates a nipe folder, clone the files into the nipe folder and cd into it
    git clone https://github.com/htrgouvea/nipe && cd nipe
    #~ Install tool that simplifies the installation, upgrading, and management of Perl modules from CPAN
    sudo apt-get install -y cpanminus
    #~ Install relevant codes / applications required to run nipe
    cpanm --installdeps --notest .
    #~ Installation of the above perl modules
    sudo cpan install Switch JSON LWP::UserAgent Config::Simple
    #~ Runs nipe.pl to install Nipe
    sudo perl nipe.pl install
    
    
    echo "Nipe installed successfully. Please run the script again to start Nipe."
fi
