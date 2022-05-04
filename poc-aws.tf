terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}
###################################
###			Create a VPC		###
###################################
resource "aws_vpc" "dev_vpc" {
  cidr_block = var.vpc-cidr
  instance_tenancy = "default"
  tags = {
  	Name = var.tag-name
  }
}

#######################################
###			Create Subnets			###
#######################################
resource "aws_subnet" "dev_subnet" {
  for_each  = var.prefix
  vpc_id     = aws_vpc.dev_vpc.id
  cidr_block = each.value["cidr"]
  availability_zone = each.value["az"]

  tags = {
    Name = "${var.basename}-subnet-${each.key}"
  }
}

# Create Internet gateway and attach to vpc
resource "aws_internet_gateway" "dev_igw" {
  vpc_id = aws_vpc.dev_vpc.id

  tags = {
    Name = "dev_igw"
  }
}

###############################################################
###		Allocate EIP, Create NAT gateway and associate it	###
###############################################################
resource "aws_eip" "dev_nat_gw" {
  vpc      = true
  tags = {
  	Name = "dev_nat_gw"
  }
}

resource "aws_nat_gateway" "dev_nat_gw" {
  allocation_id = aws_eip.dev_nat_gw.id
  subnet_id     = aws_subnet.dev_subnet["pub-b"].id

  tags = {
    Name = "dev_nat_gw"
  }
}

resource "aws_eip" "ssh_gw" {
  vpc      					= true
  network_interface			= aws_network_interface.ssh_gw.id
  associate_with_private_ip	= aws_network_interface.ssh_gw.private_ip
  depends_on				= [aws_internet_gateway.dev_igw]
  tags = {
  	Name = "ssh_gw"
  }
}

###################################################
###			Configure VPC Route Tables			###
###################################################
resource "aws_default_route_table" "dev_vpc" {
  default_route_table_id = aws_vpc.dev_vpc.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.dev_nat_gw.id
  }
  tags = {
    Name = "dev_vpc_main_rt"
  }
}

resource "aws_route_table" "dev_vpc_pub" {
  vpc_id = aws_vpc.dev_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dev_igw.id
  }
  tags = {
    Name = "dev_vpc_pub_rt"
  }
}

resource "aws_route_table_association" "dev_pub_subnets" {
  for_each		= { for key, value in aws_subnet.dev_subnet: key => value
		if can(regex("pub", key))
	}  
  subnet_id		= aws_subnet.dev_subnet[each.key].id
  route_table_id = aws_route_table.dev_vpc_pub.id
}

###################################################
### 			Create Security Group			###
###################################################

#########################
# SSH-gw Security Group #
#########################
resource "aws_security_group" "ssh_gw_sg" {
  name        = "ssh_gw_sg"
  description = "Security Group to allow ssh access to the ssh gateway"
  vpc_id      = aws_vpc.dev_vpc.id
  ingress {
      	description      = "Allow SSH"
    	from_port        = 22
    	to_port          = 22
    	protocol         = "tcp"
    	cidr_blocks      = ["139.0.240.126/32"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "ssh_gw"
  }
}

############################
# Front-end Security Group #
############################
resource "aws_security_group" "web_svr_sg" {
  name        = "web_svr_sg"
  description = "Security Group to allow internet web inbound traffic"
  vpc_id      = aws_vpc.dev_vpc.id
  dynamic ingress {
  	for_each		 = var.web_svr_sg
    content {
    	description      = ingress.value.description
    	from_port        = ingress.value.from_port
    	to_port          = ingress.value.to_port
    	protocol         = ingress.value.protocol
    	cidr_blocks      = ingress.value.cidr_blocks
  	}
  }
  dynamic ingress {
  	for_each		 = aws_network_interface.ssh_gw.private_ip_list
    content {
  		description      = "Allow SSH"
    	from_port        = 22
    	to_port          = 22
    	protocol         = "tcp"
    	cidr_blocks      = ["${ingress.value}/32"]
  	}
  }     

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "web_svr"
  }
}

#############################
# Back-end-A Security Group #
#############################
resource "aws_security_group" "back_end_a_sg" {
  name        = "back_end_a_sg"
  description = "Security Group to allow access to Back-end-A web server traffic"
  vpc_id      = aws_vpc.dev_vpc.id
  dynamic ingress {
  	for_each		= { for key, value in var.prefix: key => value
		if can(regex("fe-priv", key))
		}      
 	content {
    	description      = "http from front end"
    	from_port        = 80
    	to_port          = 80
    	protocol         = "tcp"
    	cidr_blocks      = [ingress.value.cidr]
  	}
  }
  dynamic ingress {
  	for_each		= { for key, value in var.prefix: key => value
		if can(regex("fe-priv", key))
		}      
 	content {
    	description      = "https from front end"
    	from_port        = 443
    	to_port          = 443
    	protocol         = "tcp"
    	cidr_blocks      = [ingress.value.cidr]
  	}
  }
  dynamic ingress {
    	for_each		= { for key, value in var.prefix: key => value
		if can(regex("bea-priv", key))
		}      
	content {
    	description      = "http for alb health check"
    	from_port        = 80
    	to_port          = 80
    	protocol         = "tcp"
    	cidr_blocks      = [ingress.value.cidr]
  	}
  }
  dynamic ingress {
    	for_each		= { for key, value in var.prefix: key => value
		if can(regex("bea-priv", key))
		}      
	content {
    	description      = "https for alb health check"
    	from_port        = 443
    	to_port          = 443
    	protocol         = "tcp"
    	cidr_blocks      = [ingress.value.cidr]
  	}
  }
  dynamic ingress {
  	for_each		 = aws_network_interface.ssh_gw.private_ip_list
    content {
  		description      = "Allow SSH"
    	from_port        = 22
    	to_port          = 22
    	protocol         = "tcp"
    	cidr_blocks      = ["${ingress.value}/32"]
  	}
  }     
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "back_end_a"
  }
}

#############################
# Back-end-A Security Group #
#############################
resource "aws_security_group" "back_end_b_sg" {
  name        = "back_end_b_sg"
  description = "Security Group to allow access to Back-end-b web server traffic"
  vpc_id      = aws_vpc.dev_vpc.id
  dynamic ingress {
  	for_each		= { for key, value in var.prefix: key => value
		if can(regex("fe-priv", key))
		}      
 	content {
    	description      = "http from front end"
    	from_port        = 80
    	to_port          = 80
    	protocol         = "tcp"
    	cidr_blocks      = [ingress.value.cidr]
  	}
  }
  dynamic ingress {
  	for_each		= { for key, value in var.prefix: key => value
		if can(regex("fe-priv", key))
		}      
 	content {
    	description      = "https from front end"
    	from_port        = 443
    	to_port          = 443
    	protocol         = "tcp"
    	cidr_blocks      = [ingress.value.cidr]
  	}
  }
  dynamic ingress {
    	for_each		= { for key, value in var.prefix: key => value
		if can(regex("beb-priv", key))
		}      
	content {
    	description      = "http for alb health check"
    	from_port        = 80
    	to_port          = 80
    	protocol         = "tcp"
    	cidr_blocks      = [ingress.value.cidr]
  	}
  }
  dynamic ingress {
    	for_each		= { for key, value in var.prefix: key => value
		if can(regex("beb-priv", key))
		}      
	content {
    	description      = "https for alb health check"
    	from_port        = 443
    	to_port          = 443
    	protocol         = "tcp"
    	cidr_blocks      = [ingress.value.cidr]
  	}
  }
  dynamic ingress {
  	for_each		 = aws_network_interface.ssh_gw.private_ip_list
    content {
  		description      = "Allow SSH"
    	from_port        = 22
    	to_port          = 22
    	protocol         = "tcp"
    	cidr_blocks      = ["${ingress.value}/32"]
  	}
  }     
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "back_end_b"
  }
}

#############################
# DB-A Security Group #
#############################
resource "aws_security_group" "db_a_sg" {
  name        = "db_a_sg"
  description = "Security Group to allow access to database-a server"
  vpc_id      = aws_vpc.dev_vpc.id
  dynamic ingress {
  	for_each		= { for key, value in var.prefix: key => value
		if can(regex("bea-priv", key))
		}      
 	content {
    	description      = "postgre access from back-end-a"
    	from_port        = 5432
    	to_port          = 5432
    	protocol         = "tcp"
    	cidr_blocks      = [ingress.value.cidr]
  	}
  }
  dynamic ingress {
  	for_each		 = aws_network_interface.ssh_gw.private_ip_list
    content {
  		description      = "Allow SSH"
    	from_port        = 22
    	to_port          = 22
    	protocol         = "tcp"
    	cidr_blocks      = ["${ingress.value}/32"]
  	}
  }     
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "database_a"
  }
}

#############################
# DB-B Security Group #
#############################
resource "aws_security_group" "db_b_sg" {
  name        = "db_b_sg"
  description = "Security Group to allow access to database-b server"
  vpc_id      = aws_vpc.dev_vpc.id
  dynamic ingress {
  	for_each		= { for key, value in var.prefix: key => value
		if can(regex("beb-priv", key))
		}      
 	content {
    	description      = "postgre access from back-end-b"
    	from_port        = 5432
    	to_port          = 5432
    	protocol         = "tcp"
    	cidr_blocks      = [ingress.value.cidr]
  	}
  }
  dynamic ingress {
  	for_each		 = aws_network_interface.ssh_gw.private_ip_list
    content {
  		description      = "Allow SSH"
    	from_port        = 22
    	to_port          = 22
    	protocol         = "tcp"
    	cidr_blocks      = ["${ingress.value}/32"]
  	}
  }     
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "database_b"
  }
}

#######################################################	
### 			Create Network Interface			###
#######################################################

resource "aws_network_interface" "ssh_gw" {
  subnet_id       = aws_subnet.dev_subnet["pub-a"].id
  security_groups = [aws_security_group.ssh_gw_sg.id]
}

resource "aws_network_interface" "front_end_svr" {
  for_each		= { for key, value in aws_subnet.dev_subnet: key => value
		if can(regex("fe-priv", key))
	}  
  subnet_id       = aws_subnet.dev_subnet[each.key].id
  security_groups = [aws_security_group.web_svr_sg.id]
  tags = {
  	Name = "front_end_svr-${each.key}"
  }
}

###############################################
### 			Create EC2 Instance			###
###############################################

resource "aws_instance" "ssh_gw" {
  ami           = "ami-049f20cccc294bb90" 
  instance_type = "t2.micro"
  key_name		= "edith-tf"

  network_interface {
    network_interface_id = aws_network_interface.ssh_gw.id
    device_index         = 0
  }
  tags = {
  	Name = "ssh_gw"
  }
  
}
resource "null_resource" "ssh_gw_provisioner" {
  triggers = {
    public_ip = aws_instance.ssh_gw.public_ip
  }

  connection {
    type  = "ssh"
    host  = aws_instance.ssh_gw.public_ip
    user  = "ec2-user"
	private_key = file("~/Downloads/edith-tf.pem")
    agent = true
  }
  provisioner "file" {
    source      = "~/Downloads/edith-tf.pem"
    destination = "/home/ec2-user/.ssh/edith-tf.pem"
  } 

  provisioner "remote-exec" {
    inline = [
      "chmod 400 /home/ec2-user/.ssh/edith-tf.pem",
        ]
  }
}

###########################################
### 		Create Transit Gateway		###
###########################################
resource "aws_ec2_transit_gateway" "dev-tgw" {
  description = "testing create tgw"
  auto_accept_shared_attachments = "enable"
  amazon_side_asn = "65101"
  tags = {
  	Name = "dev_tgw"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "dev-tgw-to-dev-vpc" {
#   for_each  		 = { for key, value in var.prefix: key => value
# 		if can(regex("beb-priv", key))
# 		}      
#  subnet_ids         = [aws_subnet.dev_subnet[each.key].id]
  subnet_ids         = [aws_subnet.dev_subnet["beb-priv-a"].id, aws_subnet.dev_subnet["beb-priv-b"].id, aws_subnet.dev_subnet["beb-priv-c"].id]
  transit_gateway_id = aws_ec2_transit_gateway.dev-tgw.id
  vpc_id             = aws_vpc.dev_vpc.id
  tags = {
  	Name = "dev-tgw-to-dev-vpc"
  }
}

###########################################
### 		Create Resource share		###
###########################################
resource "aws_ram_resource_share" "dev-tgw-ram" {
  name                      = "dev-tgw-ram"
  allow_external_principals = true

  tags = {
    Environment = "dev-tgw-ram"
  }
}
resource "aws_ram_principal_association" "dev-tgw-ram" {
  principal          = "996956017395"
  resource_share_arn = aws_ram_resource_share.dev-tgw-ram.arn 
}

resource "aws_ram_resource_association" "dev-tgw-ram" {
  resource_arn       = aws_ec2_transit_gateway.dev-tgw.arn
  resource_share_arn = aws_ram_resource_share.dev-tgw-ram.arn
}