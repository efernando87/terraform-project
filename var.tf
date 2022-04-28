variable "tag-name" {
   default = "dev-vpc"
}

variable "vpc-cidr" {
   default = "10.0.0.0/19"
}

variable "basename" {
   description = "Prefix used for all resources names"
   default = "dev"
}

variable "prefix" {
   type = map
   default = {
      pub-a = {
         az = "ap-southeast-1a"
         cidr = "10.0.0.0/24"
      }
      pub-b = {
         az = "ap-southeast-1b"
         cidr = "10.0.1.0/24"
      }
      pub-c = {
         az = "ap-southeast-1c"
         cidr = "10.0.2.0/24"
      }
      fe-priv-a = {
         az = "ap-southeast-1a"
         cidr = "10.0.3.0/24"
      }
      fe-priv-b = {
         az = "ap-southeast-1b"
         cidr = "10.0.4.0/24"
      }
      fe-priv-c = {
         az = "ap-southeast-1c"
         cidr = "10.0.5.0/24"
      }
      bea-priv-a = {
         az = "ap-southeast-1a"
         cidr = "10.0.6.0/24"
      }
      bea-priv-b = {
         az = "ap-southeast-1b"
         cidr = "10.0.7.0/24"
      }
      bea-priv-c = {
         az = "ap-southeast-1c"
         cidr = "10.0.8.0/24"
      }
      beb-priv-a = {
         az = "ap-southeast-1a"
         cidr = "10.0.9.0/24"
      }
      beb-priv-b = {
         az = "ap-southeast-1b"
         cidr = "10.0.10.0/24"
      }
      beb-priv-c = {
         az = "ap-southeast-1c"
         cidr = "10.0.11.0/24"
      }
      db-priv-a = {
         az = "ap-southeast-1a"
         cidr = "10.0.12.0/24"
      }
      db-priv-b = {
         az = "ap-southeast-1b"
         cidr = "10.0.13.0/24"
      }
      db-priv-c = {
         az = "ap-southeast-1c"
         cidr = "10.0.14.0/24"
      }
   }
}

variable "web_svr_sg" {
	type = map
	default = {
 		100 = {
 		    description      = "http any"
    		from_port        = 80
    		to_port          = 80
    		protocol         = "tcp"
    		cidr_blocks      = ["0.0.0.0/0"]
 			},
 		101 = {
 		    description      = "https any"
    		from_port        = 443
    		to_port          = 443
    		protocol         = "tcp"
    		cidr_blocks      = ["0.0.0.0/0"]
 			}
 	}
}

