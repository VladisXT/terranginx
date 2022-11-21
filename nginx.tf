terraform {
required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.49.0"
    }
     selectel = {
      source  = "selectel/selectel"
      version = "~> 3.9.0"
   }
  }
}
provider "openstack" {
  auth_url    = "https://api.selvpc.ru/identity/v3"
  domain_name = "236816"
  tenant_id = "062db4f400bd4e67a416979fcf9d5fc1"
  user_name   = "Jaconda"
  password    = "DRynneX6YS0l"
  region      = var.region
}
provider "selectel" {
  token = "zO2ribZe4lY4HLGSwa9wrCv0R_236816"
}
resource "openstack_compute_keypair_v2" "key_tf" {
  name       = "key_tf"
  region     = var.region
  public_key = "${file("/Users/helennikitskaya/.ssh/id_rsa.pub")}"
}
data "openstack_networking_network_v2" "external_net" {
  name = "external-network"
}
resource "openstack_networking_router_v2" "router_tf" {
  name                = "router_tf"
  external_network_id = data.openstack_networking_network_v2.external_net.id
}
resource "openstack_networking_network_v2" "network_tf" {
  name = "network_tf"
}
resource "openstack_networking_subnet_v2" "subnet_tf" {
  network_id = openstack_networking_network_v2.network_tf.id
  name       = "subnet_tf"
  cidr       = var.subnet_cidr
}
resource "openstack_networking_router_interface_v2" "router_interface_tf" {
  router_id = openstack_networking_router_v2.router_tf.id
  subnet_id = openstack_networking_subnet_v2.subnet_tf.id
}
data "openstack_images_image_v2" "ubuntu_image" {
  most_recent = true
  visibility  = "public"
  name        = "Ubuntu 22.04 LTS 64-bit"
}
resource "random_string" "random_name_server" {
  length  = 16
  special = false
}
resource "openstack_compute_flavor_v2" "flavor_server" {
  name      = "server-${random_string.random_name_server.result}"
  ram       = "1024"
  vcpus     = "1"
  disk      = "0"
  is_public = "false"
}
resource "openstack_blockstorage_volume_v3" "volume_server" {
  name                 = "volume-for-server1"
  size                 = "5"
  image_id             = data.openstack_images_image_v2.ubuntu_image.id
  volume_type          = var.volume_type
  availability_zone    = var.az_zone
  enable_online_resize = true
  lifecycle {
    ignore_changes = [image_id]
  }
}
resource "openstack_compute_instance_v2" "server_for_nginx" {
  name              = "server_for_nginx"
  flavor_id         = openstack_compute_flavor_v2.flavor_server.id
  key_pair          = openstack_compute_keypair_v2.key_tf.id
  availability_zone = var.az_zone
  network {
    uuid = openstack_networking_network_v2.network_tf.id
  }
  block_device {
    uuid             = openstack_blockstorage_volume_v3.volume_server.id
    source_type      = "volume"
    destination_type = "volume"
    boot_index       = 0
  }
  vendor_options {
    ignore_resize_confirmation = true
  }
  lifecycle {
    ignore_changes = [image_id]
  }
}
resource "openstack_networking_floatingip_v2" "fip_tf" {
  pool = "external-network"
}
resource "openstack_compute_floatingip_associate_v2" "fip_tf" {
  floating_ip = openstack_networking_floatingip_v2.fip_tf.address
  instance_id = openstack_compute_instance_v2.server_for_nginx.id
}


resource "null_resource" "configure" {
provisioner "remote-exec" {
	connection {
    		type        = "ssh"
    		user        = "root"
    		host        = "${openstack_compute_floatingip_associate_v2.fip_tf.floating_ip}"
    		private_key = "${file("/Users/helennikitskaya/.ssh/id_rsa")}"
}
    inline = [
"apt -y install --no-install-recommends wget gnupg ca-certificates",
"wget -O - https://openresty.org/package/pubkey.gpg | sudo gpg --dearmor -o /usr/share/keyrings/openresty.gpg",
"echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/ubuntu $(lsb_release -sc) main\" | sudo tee /etc/apt/sources.list.d/openresty.list > /dev/null",
"apt update -y",
"apt -y install openresty",
"mkdir /usr/local/openresty/nginx/scripts",
"rm -rf /usr/local/openrestry/nginx/html/*.html",
] 
 }
provisioner "file" {
connection {
                type        = "ssh"
                user        = "root"
                host        = "${openstack_compute_floatingip_associate_v2.fip_tf.floating_ip}"
		private_key = "${file("/Users/helennikitskaya/.ssh/id_rsa")}"
}
        source  = "nginx.conf"
        destination = "/etc/openresty/nginx.conf"
}
provisioner "file" {
connection {
                type        = "ssh"
                user        = "root"
                host        = "${openstack_compute_floatingip_associate_v2.fip_tf.floating_ip}"
		private_key = "${file("/Users/helennikitskaya/.ssh/id_rsa")}"
}
        source = "check-port.py"
        destination = "/usr/local/openresty/nginx/scripts/check-port.py"
}

provisioner "file" {
	connection {
                type        = "ssh"
                user        = "root"
                host        = "${openstack_compute_floatingip_associate_v2.fip_tf.floating_ip}"
                private_key = "${file("/Users/helennikitskaya/.ssh/id_rsa")}"
}
	destination = "/usr/local/openresty/nginx/html/index.html"
	content     = templatefile("index.html.tftpl", {ip_addr = openstack_compute_floatingip_associate_v2.fip_tf.floating_ip}) 
}

provisioner "remote-exec" {
connection {
                type        = "ssh"
                user        = "root"
                host        = "${openstack_compute_floatingip_associate_v2.fip_tf.floating_ip}"
		private_key = "${file("/Users/helennikitskaya/.ssh/id_rsa")}"
}
        inline = [
"chmod 755 /usr/local/openresty/nginx/scripts/check-port.py",
"systemctl restart openresty.service",
]        
}
}
