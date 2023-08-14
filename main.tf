#Add cloud provider
provider "aws" {
    access_key = "AKIARUKTUTE3IKQ3CHSA"
    secret_key = "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"
    region = "us-east-1"
}

#Create a VPC 
resource "aws_vpc" "prod_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    
Name = "production"
  }
}

#Create an Internet Gateway
resource "aws_internet_gateway" "prod_igw" {
    vpc_id = aws_vpc.prod_vpc.id
}



#Create public & private subnet
resource "aws_subnet" "public_subnet" {
    vpc_id = aws_vpc.prod_vpc.id
    cidr_block = "10.0.0.0/26"
    map_public_ip_on_launch = true
    availability_zone = "us-east-1a"
    tags = {
        Name = "pub_subnet"
    }
}

resource "aws_subnet" "private_subnet" {
    vpc_id = aws_vpc.prod_vpc.id
    cidr_block = "10.0.0.64/26"
    availability_zone = "us-east-1b"
    map_public_ip_on_launch = false
    tags = {
        Name = "priv_subnet"
    }
}
#Create Route tables for public and private subnet
#Public SUbnet
resource "aws_route_table" "public_route_table" {
    vpc_id = aws_vpc.prod_vpc.id 
       route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.prod_igw.id
        }
    tags = {
        Name = "public_route"
    }    
}
#Create a NAT gateway
resource "aws_nat_gateway" "my_nat_gateway" {
    allocation_id = aws_eip.my_eip.id
    subnet_id     = aws_subnet.public_subnet.id
}

resource "aws_eip" "my_eip" {
  vpc = true
}

#Private SUbnet
resource "aws_route_table" "private_route_table" {
    vpc_id = aws_vpc.prod_vpc.id
           route {
                cidr_block = "0.0.0.0/0"
                nat_gateway_id = aws_nat_gateway.my_nat_gateway.id 
                      }
                     
    tags = {
        Name = "private_route"
    } 
}

# Create public and private route table associatetion 
#Public associattion 
resource "aws_route_table_association" "public_associattion" { 
    subnet_id = aws_subnet.public_subnet.id
    route_table_id = aws_route_table.public_route_table.id
}
#Private association 
resource "aws_route_table_association" "private_association" {
    subnet_id = aws_subnet.private_subnet.id
    route_table_id = aws_route_table.private_route_table.id
}

#Create a security Group
resource "aws_security_group" "infra_sg" {
    vpc_id = aws_vpc.prod_vpc.id
    name = "infra-security-group"
    tags = {
        Name = "infra-security-group"
    }
    # Inbound rules (allow incoming traffic)
    ingress  {
        description = "http"
        from_port  = 80
        to_port    = 80
        protocol   = "tcp"
        cidr_blocks = ["0.0.0.0/0"]  // Allow traffic from any IP address (for demonstration purposes)
    }
    ingress  {
        description = "all"
        from_port  = 0
        to_port    = 0
        protocol   = "all"
        cidr_blocks = ["0.0.0.0/0"]  // Outbound rules (allow outgoing traffic)
    }   
    egress {
        description = "all outbound"
        from_port   = 0
        to_port     = 0
        protocol    = "-1"  // Allow all outbound traffic
        cidr_blocks = ["0.0.0.0/0"]
    }
   }
# Create a Network Interface Card for Public and private for EC2 
#Public N/W Interface
resource "aws_network_interface" "pubic_nw_interface" {
    subnet_id = aws_subnet.public_subnet.id
    private_ips = ["10.0.0.5"] # Specify the desired private IP addresses
  }
#Private N/W interface
resource "aws_network_interface" "private_nw_interface" {
    subnet_id = aws_subnet.private_subnet.id
    private_ips = ["10.0.0.70"] # Specify the desired private IP addresses
}  

#Create an Instance with public & private environment
#public instance
resource "aws_instance" "public_instance" {
    ami = "ami-0a0c8eebcdd6dcbd0" 
    instance_type = "a1.medium"
    key_name = "test-key"
    subnet_id = aws_subnet.public_subnet.id
    security_groups = [aws_security_group.infra_sg.id]
    tags = {
      Name = "public_instance"
    }
    provisioner "remote-exec" {
        connection {
            type        = "ssh"
            user        = "ubuntu"  # Replace with the appropriate username
            private_key = file("C:/Users/Administrator/Desktop/infra/test-key.pem")  # Replace with the path to your private key
            host        = aws_instance.public_instance.public_ip
          }
        inline = [
            "sudo apt update",
            "sudo apt install -y default-jdk",     # Install Java
            "sudo apt install -y tomcat9 tomcat9-admin", # Install Tomcat
            "sudo systemctl start tomcat9",        # Start Tomcat
            "sudo systemctl enable tomcat9"        # Enable Tomcat to start on boot
    ]
  }
}
#Private Instance
resource "aws_instance" "private_instance" {
    ami = "ami-0a0c8eebcdd6dcbd0" 
    instance_type = "t4g.small"
    key_name = "test-key"
    subnet_id = aws_subnet.private_subnet.id
    security_groups = [aws_security_group.infra_sg.id]
    tags = {
        Name = "private_instance"
    }
}

#create a Load balancer 
resource "aws_lb" "alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups   = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet.id, aws_subnet.private_subnet.id]  # Replace with your subnet IDs

  enable_deletion_protection = false
}

resource "aws_security_group" "alb_sg" {
  name_prefix = "alb_sg_"
  vpc_id = aws_vpc.prod_vpc.id
  tags = {
    Name = "alb-sg"
  }
}

resource "aws_lb_target_group" "ec2_target_group" {
  name     = "ec2-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.prod_vpc.id  # Replace with your VPC ID
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
            
            status_code      = "400"
            content_type     = "text/plain"
        }   
    }
}
resource "aws_lb_listener_rule" "alb_listener_rule" {
  listener_arn = aws_lb_listener.alb_listener.id

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2_target_group.arn
  }

  condition {
    path_pattern {
      values = ["/"]
    }
  }
}
#EC2 target attachment
resource "aws_lb_target_group_attachment" "target1" {
  target_group_arn = aws_lb_target_group.ec2_target_group.arn
  target_id        = aws_instance.public_instance.id
  port             = 80
}
#resource "aws_lb_target_group_attachment" "target2" {
#  target_group_arn = aws_lb_target_group.ec2_target_group.arn
#  target_id        = aws_instance.private_instance.id
#  port             = 80
#}

#Create a Launch Configuration
resource "aws_launch_configuration" "launch_conf" {
  name_prefix          = "launch"
  image_id             = "ami-097d5b19d4f1a7d1b"  # Replace with your desired AMI ID
  instance_type       = "a1.large"      # Replace with your desired instance type
  security_groups     =  ["sg-0624539a84100e038"]  # Replace with your security group(s)
  key_name             = "test-key"
}
#Create an Auto Scaling Group
resource "aws_autoscaling_group" "scale_asg" {
  name                 = "scale_asg"
  launch_configuration = aws_launch_configuration.launch_conf.name
  min_size             = 1
  max_size             = 2
  desired_capacity     = 1
  health_check_type    = "EC2" # Use "EC2" or "ELB" depending on your needs
  health_check_grace_period = "50"
  vpc_zone_identifier  = [aws_subnet.private_subnet.id]
  
  tag {
    key                 = "Name"
    value               = "scale-instance"
    propagate_at_launch = true
  }
}
#Create Auto Scaling Policy:
resource "aws_autoscaling_policy" "example" {
  name                   = "auto-scaling-policy"
  policy_type            = "TargetTrackingScaling"
  estimated_instance_warmup = 120
  autoscaling_group_name = aws_autoscaling_group.scale_asg.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 80.0
  }
}

#Attach Auto Scaling Group to Load Balancer
resource "aws_autoscaling_attachment" "scale_attach" {
  autoscaling_group_name = aws_autoscaling_group.scale_asg.name
  lb_target_group_arn   = aws_lb_target_group.ec2_target_group.arn
}
