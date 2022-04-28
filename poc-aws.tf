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
  subnet_id       = aws_subnet.dev_subnet["pub-b"].id
  private_ips     = ["10.0.1.10", "10.0.1.11"]
  security_groups = [aws_security_group.ssh_gw_sg.id]
}

resource "aws_network_interface" "front_end_svr" {
  for_each		= { for key, value in aws_subnet.dev_subnet: key => value
		if can(regex("fe-priv", key))
	}  
  subnet_id       = aws_subnet.dev_subnet[each.key].id
  security_groups = [aws_security_group.web_svr_sg.id]
  private_ips_count = 1
  tags = {
  	Name = "front_end_svr-${each.key}"
  }
}
